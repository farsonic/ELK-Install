#!/bin/bash

# Warning before proceeding
echo "WARNING: This script will uninstall Docker, the Pensando ELK Stack, its related tools, and some configuration changes from your system. Continue? (y/n)"
read proceed
if [[ $proceed != "y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Ensure the script is being run on Ubuntu
if [[ "$(lsb_release -si)" != "Ubuntu" ]]; then
    echo "This script is designed for Ubuntu Server. Exiting."
    exit 1
fi

# Stop the Docker containers
if command -v docker-compose &>/dev/null && [ -f "./elk-pensando/docker-compose.yml" ]; then
    cd elk-pensando
    docker-compose down
    cd ..
fi

# Remove the user from the Docker group
sudo gpasswd -d $USER docker

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
sudo usermod -G $(groups $(whoami) | sed 's/ /\,/g' | sed 's/,docker//g' | cut -d: -f2 | sed 's/^ //') $(whoami)

echo "Uninstallation completed!"
