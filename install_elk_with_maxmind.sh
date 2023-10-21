#!/bin/bash

# Ensure the script is being run on Ubuntu
if [[ "$(lsb_release -si)" != "Ubuntu" ]]; then
    echo "This script is designed for Ubuntu. Exiting."
    exit 1
fi


# Check for minimum RAM requirement of 16GB
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if (( TOTAL_RAM < 16384 )); then
    echo "Warning: Your system has less than the recommended 16GB of RAM ($TOTAL_RAM MB detected)."
    read -p "Acknowledge that 16GB or more of RAM is recommended before proceeding (y/n): " RAM_ACK
fi

# Check for minimum disk space requirement of 500GB
ROOT_DISK_SPACE=$(df --output=size -BG / | tail -1 | tr -d 'G')
if (( ROOT_DISK_SPACE < 500 )); then
    echo "Warning: Your system has less than the recommended 500GB of disk space ($ROOT_DISK_SPACE GB detected)."
    read -p "Acknowledge that 500GB or more of disk space is recommended before proceeding (y/n): " DISK_ACK
fi

# Install required tools and Docker
if ! command -v docker &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose
    sudo usermod -aG docker $USER
    newgrp docker
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    service docker start
fi

# Fetch the available branches
BRANCHES=$(git ls-remote --heads https://gitlab.com/pensando/tbd/siem/elastic/elk-pensando | awk -F'/' '{print $3}')

echo "Available branches:"

while true; do
    select BRANCH_NAME in $BRANCHES; do
        if [[ -n $BRANCH_NAME ]]; then
            break 2
        else
            echo "Invalid selection. Please choose a valid number from the list."
            break
        fi
    done
done

echo "Selected branch: $BRANCH_NAME"

REPO_DIR="elk-pensando"
REPO_URL="https://gitlab.com/pensando/tbd/siem/elastic/elk-pensando.git"

# Check if the directory exists
if [ -d "$REPO_DIR" ]; then
    echo "Local clone exists. Updating..."
    cd $REPO_DIR
    git pull origin $BRANCH_NAME
else
    echo "Cloning repository..."
    git clone -b $BRANCH_NAME $REPO_URL
    cd $REPO_DIR
fi

# Set the Elastic version, with a default known functional version of 8.6.2
read -p "Please enter the Elastic version you want to use (default: 8.6.2): " ELASTIC_VERSION
ELASTIC_VERSION=${ELASTIC_VERSION:-8.6.2}
echo "TAG=$ELASTIC_VERSION" > .env

# Prompt user for version with a default value
read -p "Please enter the Elastiflow version you want to use (default: 6.3.5): " ELASTIFLOW_VERSION
ELASTIFLOW_VERSION=${ELASTIFLOW_VERSION:-6.3.5}

# Replace the version in the docker-compose.yml file
sed -i "s|elastiflow/flow-collector:[^ ]*|elastiflow/flow-collector:$ELASTIFLOW_VERSION|" docker-compose.yml


# Directory setup and permissions
mkdir -p ./data/es_backups ./data/pensando_es ./data/elastiflow
chmod -R 777 ./data

# Update vm.max_map_count for Elasticsearch
sudo sysctl -w vm.max_map_count=262144
echo vm.max_map_count=262144 | sudo tee -a /etc/sysctl.conf

read -p "Are you going to collect IPFix packets? (y/n): " COLLECT_IPFIX
if [ "$COLLECT_IPFIX" == "y" ]; then
    sed -i "s/EF_OUTPUT_ELASTICSEARCH_ENABLE: 'false'/EF_OUTPUT_ELASTICSEARCH_ENABLE: 'true'/" docker-compose.yml
    read -p "Enter the IP address of your system (This needs to be reachable from dataplane interface on CX10000: " SYSTEM_IP
    sed -i "s/CHANGEME:9200/$SYSTEM_IP:9200/" docker-compose.yml
fi

# Run the containers
docker-compose up --detach

# Wait for Elasticsearch to become available
echo "Waiting for Elasticsearch to become available..."
while ! curl -s "http://localhost:9200/" &>/dev/null; do
    sleep 5
done

# Configure the Elasticsearch index template
echo "Configuring Elasticsearch index template..."
while : ; do
    RESPONSE=$(curl -s -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_index_template/pensando-fwlog?pretty' -d @./elasticsearch/pensando_fwlog_mapping.json)
    if [[ $(echo "$RESPONSE" | jq -r '.acknowledged') == "true" ]]; then
        break
    fi
    sleep 5
done

while : ; do
    RESPONSE=$(curl -s -XPOST -H 'Content-Type: application/json' 'http://localhost:9200/_license/start_trial?acknowledge=true')
    
    ACKNOWLEDGED=$(echo "$RESPONSE" | jq -r '.acknowledged')
    
    if [[ "$ACKNOWLEDGED" == "true" ]]; then
        echo "Elasticsearch trial license installed successfully."
        break
    else
        echo "Waiting for Elasticsearch trial license to be configured..."
        sleep 5
    fi
done

read -p "Do you want to install the maxmind databases? (y/n): " INSTALL_MAXMIND
if [[ "$INSTALL_MAXMIND" == "y" ]]; then
    read -p "Enter your Maxmind API Key: " MAXMIND_API_KEY
    
    # Downloading the files
    curl -o GeoLite2-ASN.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key=$MAXMIND_API_KEY&suffix=tar.gz"
    curl -o GeoLite2-City.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=$MAXMIND_API_KEY&suffix=tar.gz"
    
    # Modify the docker-compose.yml file
    sed -i "s/EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE: 'false'/EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE: 'true'/" docker-compose.yml
    sed -i "s/EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE: 'false'/EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE: 'true'/" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_PATH: '/etc/elastiflow/maxmind/GeoLite2-City.mmdb'|EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_PATH: '/etc/elastiflow/maxmind/GeoLite2-City.mmdb'|" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_PATH: '/etc/elastiflow/maxmind/GeoLite2-ASN.mmdb'|EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_PATH: '/etc/elastiflow/maxmind/GeoLite2-ASN.mmdb'|" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_VALUES: 'city,country,country_code,location,timezone'|EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_VALUES: 'city,country,country_code,location,timezone'|" docker-compose.yml

    # Create directory in elastiflow container and copy the files
    docker exec -it pensando-elastiflow mkdir -p /etc/elastiflow/maxmind
    docker cp GeoLite2-ASN.tar.gz pensando-elastiflow:/etc/elastiflow/maxmind/
    docker cp GeoLite2-City.tar.gz pensando-elastiflow:/etc/elastiflow/maxmind/

    # Get the user ID and group ID of the user running inside the container
    USER_ID=$(docker exec pensando-elastiflow id -u)
    GROUP_ID=$(docker exec pensando-elastiflow id -g)
    
    # Untar the files in the elastiflow container as that user
    docker exec -u $USER_ID -it pensando-elastiflow bash -c "tar -xzf /etc/elastiflow/maxmind/GeoLite2-ASN.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/"
    docker exec -u $USER_ID -it pensando-elastiflow bash -c "tar -xzf /etc/elastiflow/maxmind/GeoLite2-City.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/"

fi

read -p "Do you want to install RiskIQ Components? (y/n): " INSTALL_RISKIQ
if [[ "$INSTALL_RISKIQ" == "y" ]]; then
    read -p "Enter your RiskIQ Account Number: " RISKIQ_ACCOUNT
    read -p "Enter your RiskIQ Account Email: " RISKIQ_EMAIL
    read -p "Enter your RiskIQ Account Encryption Key: " RISKIQ_ENCRYPTION_KEY
    read -p "Enter your RiskIQ Account UUID: " RISKIQ_UUID
    read -p "Enter your RiskIQ License API Key: " RISKIQ_API_KEY

    # Modify the docker-compose.yml file
    sed -i "s|EF_FLOW_OUTPUT_RISKIQ_ENABLE: 'false'|EF_OUTPUT_RISKIQ_ENABLE: 'true'|g" docker-compose.yml
    sed -i "s|#EF_FLOW_OUTPUT_RISKIQ_HOST:'|EF_OUTPUT_RISKIQ_HOST: 'flow.riskiq.net'|g" docker-compose.yml
    sed -i "s|#EF_FLOW_OUTPUT_RISKIQ_PORT:'|EF_OUTPUT_RISKIQ_PORT: 20000'|g" docker-compose.yml
    sed -i "s|#EF_ACCOUNT_ID: ''|EF_ACCOUNT_ID: '$RISKIQ_ACCOUNT'|g" docker-compose.yml
    sed -i "s|#EF_FLOW_OUTPUT_RISKIQ_CUSTOMER_UUID: ''|EF_OUTPUT_RISKIQ_CUSTOMER_UUID: '$RISKIQ_UUID'|g" docker-compose.yml
    sed -i "s|#EF_FLOW_OUTPUT_RISKIQ_CUSTOMER_ENCRYPTION_KEY: ''|EF_OUTPUT_RISKIQ_CUSTOMER_ENCRYPTION_KEY: '$RISKIQ_ENCRYPTION_KEY'|g" docker-compose.yml
    sed -i "s|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_THREAT_ENABLE: 'false'|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_THREAT_ENABLE: 'true'|g" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_USER: ''|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_USER: '$RISKIQ_EMAIL'|g" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_KEY: ''|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_KEY: '$RISKIQ_API_KEY'|g" docker-compose.yml
fi

    


# Import all Kibana saved objects and display count of successfully imported objects
echo "Importing Kibana saved objects from elk-pensando/kibana..."
TOTAL_IMPORTED=0
for FILE in kibana/*.ndjson; do
    while : ; do  #
        RESPONSE=$(curl -s -X POST "http://localhost:5601/api/saved_objects/_import" -H "kbn-xsrf: true" --form file=@$FILE)
        if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
            IMPORTED_COUNT=$(echo "$RESPONSE" | jq '.successCount')
            TOTAL_IMPORTED=$((TOTAL_IMPORTED + IMPORTED_COUNT))
            echo "Successfully imported $IMPORTED_COUNT objects from $FILE"
            break  # Exit the loop if the import was successful
        else
            ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.errors[0].error.message')
            if [[ $ERROR_MESSAGE == *"already exists"* ]]; then
                echo "Objects in $FILE already exist. Skipping..."
                break
            else
                echo "Failed to import objects from $FILE, retrying in 5 seconds..."
                sleep 5  # Wait for 5 seconds before retrying
            fi
        fi
    done
done


echo "$TOTAL_IMPORTED objects were successfully imported into Kibana."

echo "======================== Setup Complete ========================"
echo "Access Kibana: http://<IP-Address>:5601 to view CX10000 data."
echo ""
echo "---------------------- Configuration Steps ---------------------"
echo "1. Direct all logs to both PSM and this ELK server on UDP/5514 (RFC5424):"
echo "   - Configure PSM accordingly."
echo ""
echo "2. SYSLOG Source:"
echo "   - Ensure SYSLOGs are sent from the default VRF via a front panel interface (avoid the mgmt interface)."
echo ""
echo "3. IPFIX Configuration:"
echo "   - Send IPFIX logs from a front panel interface (not the mgmt interface)."
echo "   - Configure PSM to forward IPFIX logs to UDP/9995."
echo "   - On each CX10000 CLI, set the source interface for IPFIX and enable DSM:"
echo "        > ip source-interface ipfix X.X.X.X"
echo "        > dsm ipfix"
echo "----------------------------------------------------------------"