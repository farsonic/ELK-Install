# ELK-Install

The purpose of these three scripts is to quickly install, configure and uninstall the Pensando ELK Stack. 
This has been tested on Ubuntu Server and can't be said to work on other distributions where it hasn't 
been tested. 


## Initial software installation
To install the ELK-Pensando stack execute the following script as a non root user that has sudo access. 
Do not run this as the root user. 

```
bash <(curl -s https://raw.githubusercontent.com/farsonic/ELK-Install/main/install_elk.sh)
```
## Software configuration
This will install docker, ensure the current user is a member of the docker group and pull down the required 
software. It will prompt the user for the specific version of the CXOS being deployed and which version of the 
ELK components to deploy. 

Once this install script completes all the relevant software has been downloaded but we need to finally 
configure the ELK Stack and download the required containers. The install script when completed will instruct
the user to log-off and back in again to refresh their group membership. Once you have reconnected to the server 
cd to the elk-pensando directory and run the post installation script. 

```
bash <(curl -s https://raw.githubusercontent.com/farsonic/ELK-Install/main/post_install_elk.sh)
```

This script wil make required changes to the docker-compose.yml file prior to starting the environment. There is 
a few additional components that can be installed that will require additional licenses or keys to be provided, but 
these are all optional. Go to the following sites to request or obtain a license key. 

https://www.maxmind.com/en/account/login  (Provides geo-ip information)

https://community.riskiq.com/login        (Community threat intelligence)

https://www.elastiflow.com/get-started    (Elastiflow licensing for IPFIX enrichment)

## Uninstallation and software removal 
To remove all software components and return the system to the original state execute the following command as a member
of the docker group. 

```
bash <(curl -s https://raw.githubusercontent.com/farsonic/ELK-Install/main/uninstall_elk.sh)
```

## Video Walkthrough

[<img src="https://img.youtube.com/vi/xRz7pJD_FEg/maxresdefault.jpg" width="50%">](https://youtu.be/xRz7pJD_FEg)

## Disclaimer

This is just a quick script to install the ELK-Pensando software from an existing repo. It has had minimal testing and 
is provided as is. 