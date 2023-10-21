#!/bin/bash

# Ensure the script is being run on Ubuntu
if [[ "$(lsb_release -si)" != "Ubuntu" ]]; then
    echo "This script is designed for Ubuntu. Exiting."
    exit 1
fi

# Stop the Docker containers
if command -v docker-compose &>/dev/null && [ -f "./elk-pensando/docker-compose.yml" ]; then
    cd elk-pensando
    docker-compose down
    cd ..
fi

# Remove Docker, its tools, and related packages
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose jq
sudo apt-get autoremove -y

# Remove the Docker repository and its key
sudo rm /etc/apt/keyrings/docker.gpg
sudo rm /etc/apt/sources.list.d/docker.list

# Remove the cloned Git repository
if [ -d "elk-pensando" ]; then
    rm -rf elk-pensando
fi

# Revert system changes
sudo sed -i '/vm.max_map_count=262144/d' /etc/sysctl.conf
sudo sysctl -w vm.max_map_count=$(cat /proc/sys/vm/max_map_count)

echo "Uninstallation completed!"