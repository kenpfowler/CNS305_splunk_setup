#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo $0)"
  exit 1
fi

set -eou pipefail

# temporarily disable SELinux (Security-Enhanced Linux
setenforce 0

# add firewall rules to allow splunk controller to be accessed
firewall-cmd --add-port 8000/tcp --zone=public --permanent 
firewall-cmd --add-port 8089/tcp --zone=public --permanent 
firewall-cmd --add-port 9997/tcp --zone=public --permanent 
firewall-cmd --add-port 80/tcp --zone=public --permanent 
firewall-cmd --add-port 443/tcp --zone=public --permanent 
firewall-cmd --reload

echo "Firewall rules for splunk controller set"
