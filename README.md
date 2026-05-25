# Splunk Install Scripts
These install scripts will setup Splunk on the CentOS virtual machine provided for _SEC320 - Lab1: Introduction to Incident Response at Seneca Polytechnic_.

## Prerequisites

- CentOS Virtual Machines (CentOS GUI and CentOS CLI)
- Splunk Indexer, Splunk Forwarder, and Splunk for Unix and Linux Add-On (version 8.2.4)

The controller vm needs to be configured with hostname _Controller_
```sudo hostnamectl set-hostname Controller```

Generate a unique MAC address for your cloned agents via your hypervisor

Configure the agents hostname and IP address using ```nmtui```

Agent 1: 192.168.XXX.11
Agent 2: 192.168.XXX.12 
Agent 3: 192.168.XXX.13 

## Usage

### Install Splunk Indexer on Controller
```sudo chmod u+x setup_splunk.sh```

```sudo ./setup_splunk.sh <splunk.tar.gz> <addon.tar.gz>``` 

### Install Splunk Forwarder on Agent
```sudo chmod u+x setup_splunk_forwarder.sh```

```sudo ./setup_splunk_forwarder.sh <splunkforwarder.tar.gz> <addon.tar.gz> <controller_ip>```
