if id $(whoami) | grep -q 'docker'; then
    echo "User is a member of the docker group."
else
    echo "User is NOT a member of the docker group. Exiting."
    exit 1
fi

current_dir=$(basename "$PWD")

if [ "$current_dir" = "elk-pensando" ]; then
    echo "Current directory is 'elk-pensando'."
else
    echo "Current directory is not 'elk-pensando'. Exiting."
    exit 1
fi


read -p "Are you going to collect IPFix packets? (y/n): " COLLECT_IPFIX
if [ "$COLLECT_IPFIX" == "y" ]; then
    sed -i "s/EF_OUTPUT_ELASTICSEARCH_ENABLE: 'false'/EF_OUTPUT_ELASTICSEARCH_ENABLE: 'true'/" docker-compose.yml
    read -p "Enter the IP address of your system (This needs to be reachable from dataplane interface on CX10000: " SYSTEM_IP
    sed -i "s/CHANGEME:9200/$SYSTEM_IP:9200/" docker-compose.yml
fi

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
    #read -p "Enter your RiskIQ Account Number: " RISKIQ_ACCOUNT
    read -p "Enter your RiskIQ Account Email: " RISKIQ_EMAIL
    read -p "Enter your RiskIQ Account Encryption Key: " RISKIQ_ENCRYPTION_KEY
    read -p "Enter your RiskIQ Account UUID: " RISKIQ_UUID
    read -p "Enter your RiskIQ API Key: " RISKIQ_API_KEY
    #read -p "Enter your RiskIQ License Key: " RISKIQ_LICENSE_KEY

    # Modify the docker-compose.yml file
    sed -i "s|EF_OUTPUT_RISKIQ_ENABLE: 'false'|EF_OUTPUT_RISKIQ_ENABLE: 'true'|g" docker-compose.yml
    sed -i "s|#EF_OUTPUT_RISKIQ_HOST:'|EF_OUTPUT_RISKIQ_HOST: 'flow.riskiq.net'|g" docker-compose.yml
    sed -i "s|#EF_OUTPUT_RISKIQ_PORT:'|EF_OUTPUT_RISKIQ_PORT: 20000'|g" docker-compose.yml
    sed -i "s|EF_OUTPUT_RISKIQ_ENABLE: 'false'|EF_OUTPUT_RISKIQ_ENABLE: 'true'|g" docker-compose.yml
    sed -i "s|#EF_OUTPUT_RISKIQ_CUSTOMER_UUID: ''|EF_OUTPUT_RISKIQ_CUSTOMER_UUID: '$RISKIQ_UUID'|g" docker-compose.yml
    sed -i "s|#EF_OUTPUT_RISKIQ_CUSTOMER_ENCRYPTION_KEY: ''|EF_OUTPUT_RISKIQ_CUSTOMER_ENCRYPTION_KEY: '$RISKIQ_ENCRYPTION_KEY'|g" docker-compose.yml
    sed -i "s|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_THREAT_ENABLE: 'false'|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_THREAT_ENABLE: 'true'|g" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_USER: ''|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_USER: '$RISKIQ_EMAIL'|g" docker-compose.yml
    sed -i "s|#EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_KEY: ''|EF_PROCESSOR_ENRICH_IPADDR_RISKIQ_API_KEY: '$RISKIQ_API_KEY'|g" docker-compose.yml
    #sed -i "s|#EF_FLOW_LICENSE_KEY: ''|#EF_FLOW_LICENSE_KEY: '$RISKIQ_LICENSE_KEY'|g" docker-compose.yml
fi

read -p "Do you want to apply Elastiflow licensing? (y/n): " LICENSE_ELASTIFLOW
if [[ "$LICENSE_ELASTIFLOW" == "y" ]]; then
    read -p "Enter your RiskIQ Account Number: " ELASTIFLOW_ACCOUNT
    read -p "Enter your RiskIQ License Key: " ELASTIFLOW_LICENSE_KEY
    sed -i "s|#EF_ACCOUNT_ID: ''|EF_ACCOUNT_ID: '$ELASTIFLOW_ACCOUNT'|g" docker-compose.yml
    sed -i "s|#EF_FLOW_LICENSE_KEY: ''|EF_FLOW_LICENSE_KEY: '$ELASTIFLOW_LICENSE_KEY'|g" docker-compose.yml


fi

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