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

# Check if elk-pensando directory already exists
if [ -d "elk-pensando" ]; then
    echo "The directory elk-pensando already exists. Aborting the installation."
    exit 1
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
fi

# Fetch the available branches
BRANCHES=$(git ls-remote --heads https://gitlab.com/pensando/tbd/siem/elastic/elk-pensando | awk -F'/' '{print $3}')

echo "Available branches:"
select BRANCH_NAME in $BRANCHES; do
    if [[ -n $BRANCH_NAME ]]; then
        break
    fi
done

echo "Selected branch: $BRANCH_NAME"

# Clone the repository
git clone -b $BRANCH_NAME https://gitlab.com/pensando/tbd/siem/elastic/elk-pensando.git
cd elk-pensando

# Set the Elastic version, with a default known functional version of 8.6.2
read -p "Please enter the Elastic version you want to use (default: 8.6.2): " ELASTIC_VERSION
ELASTIC_VERSION=${ELASTIC_VERSION:-8.6.2}
echo "TAG=$ELASTIC_VERSION" > .env

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

# Import all Kibana saved objects and display count of successfully imported objects
echo "Importing Kibana saved objects from elk-pensando/kibana..."
TOTAL_IMPORTED=0
for FILE in kibana/*.ndjson; do
    while : ; do  # This creates an infinite loop for each file
        RESPONSE=$(curl -s -X POST "http://localhost:5601/api/saved_objects/_import" -H "kbn-xsrf: true" --form file=@$FILE)
        if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
            IMPORTED_COUNT=$(echo "$RESPONSE" | jq '.successCount')
            TOTAL_IMPORTED=$((TOTAL_IMPORTED + IMPORTED_COUNT))
            echo "Successfully imported $IMPORTED_COUNT objects from $FILE"
            break  # Exit the loop if the import was successful
        else
            echo "Failed to import objects from $FILE, retrying in 5 seconds..."
            sleep 5  # Wait for 5 seconds before retrying
        fi
    done
done

# Additional step to download and import the Retransmit_dashboard.ndjson file
echo "Downloading and importing Retransmit_dashboard.ndjson..."
curl -s -O https://raw.githubusercontent.com/farsonic/ELK-Install/main/Retransmit_dashboard.ndjson
while : ; do
    RESPONSE=$(curl -s -X POST "http://localhost:5601/api/saved_objects/_import" -H "kbn-xsrf: true" --form file=@Retransmit_dashboard.ndjson)
    if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
        IMPORTED_COUNT=$(echo "$RESPONSE" | jq '.successCount')
        TOTAL_IMPORTED=$((TOTAL_IMPORTED + IMPORTED_COUNT))
        echo "Successfully imported $IMPORTED_COUNT objects from Retransmit_dashboard.ndjson"
        break  # Exit the loop if the import was successful
    else
        echo "Failed to import objects from Retransmit_dashboard.ndjson, retrying in 5 seconds..."
        echo "Response: $RESPONSE" 
        sleep 5  # Wait for 5 seconds before retrying
    fi
done

echo "$TOTAL_IMPORTED objects were successfully imported into Kibana."

echo "Setup complete. Open Kibana at http://<IP-Address>:5601 to view SYSLOG/IPFIX data from CX10000."
echo "==============================================================================================="
echo "Ensure you configure PSM to point all logging to both PSM and to this ELK server on UDP/5514 as RFC5424"
echo "SYSLOG should come from the default VRF over an interface on the front panel (ie not the mgmt interface)"
echo "IPFIX logs need to come from a front panel interface and will not function over the mgmt interface and configured within PSM to forward to UDP/9995"
echo "From the CLI on each CX10000 set the source interface for IPFIX and enable DSM to send IPFIX Packets"
echo "                         ->  ip source-interface ipfix X.X.X.X"
echo "                         ->  dsm ipfix"