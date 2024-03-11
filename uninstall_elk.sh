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
if command -v docker-compose &>/dev/null && [ -f "./pensando-elk/docker-compose.yml" ]; then
    cd pensando-elk
    docker compose down
    cd ..
fi

#Blow away all images
docker system prune -a

# Remove the user from the Docker group
sudo gpasswd -d $USER docker

# Remove Docker, its tools, and related packages
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose jq
sudo apt-get autoremove -y

# Remove the Docker repository and its key
sudo rm /etc/apt/keyrings/docker.gpg
sudo rm /etc/apt/sources.list.d/docker.list

for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

cd 

# Remove the cloned Git repository
if [ -d "pensando-elk" ]; then
    rm -rf pensando-elk
fi

# Revert system changes
sudo sed -i '/vm.max_map_count=262144/d' /etc/sysctl.conf
sudo sysctl -w vm.max_map_count=$(cat /proc/sys/vm/max_map_count)
sudo usermod -G $(groups $(whoami) | sed -e 's/^.*: //' -e 's/ /\,/g' | tr ',' '\n' | grep -v docker | tr '\n' ',' | sed 's/,$//') $(whoami)

echo "Uninstallation completed!"
