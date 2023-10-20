#!/bin/bash
#run with bash known_bad_hosts.sh

# Download the list of IP addresses
wget https://github.com/firehol/blocklist-ipsets/raw/master/snort_ipfilter.ipset -O ip_list.txt

# Loop through the list
while IFS= read -r ip; do
    # Check if the line starts with a #
    if [[ ! "$ip" =~ ^# ]]; then
        echo "Attempting to connect to $ip"

        # Attempt a curl connection with 5 seconds timeout
        curl --max-time 2 "http://$ip"

        # Small delay before moving to next IP, can be removed if not needed
        sleep 1
    fi
done < ip_list.txt

# Clean up the downloaded list
rm ip_list.txt