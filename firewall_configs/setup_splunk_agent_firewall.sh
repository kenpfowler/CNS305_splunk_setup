#!/bin/bash

set -eou pipefail

setenforce 0

firewall-cmd --add-port 9997/tcp --zone=public --permanent 
firewall-cmd --add-port 8089/tcp --zone=public --permanent 
firewall-cmd --reload

echo "Firewall rules for Splunk Forwarder set."

