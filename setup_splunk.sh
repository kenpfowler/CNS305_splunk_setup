#!/bin/bash

# -e exit on any error
# -u exit on unassigned variable
# -o exit on pipeline failure
set -euo pipefail

# required archives
CONTROLLER="splunk-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
AGENT="splunkforwarder-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
ADD_ON="splunk-add-on-for-unix-and-linux_870.tgz"

# expected extractions
EXTRACTED_ADD_ON="Splunk_TA_nix"
EXTRACTED_FORWARDER="splunkforwarder"
EXTRACTED_CONTROLLER="splunk"

# default root splunk enterprise
DEFAULT_ROOT="/opt"

# run script as root user
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo $0)"
  exit 1
fi

# check that two arguments are provided
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <splunk.tar.gz> <splunk_add_on.tar.gz>"
    exit 1
fi

# check if file exists at user path
if [[ ! -f "$1" ]]; then  
	echo "First argument must be type file: <archive.tar.gz>"
	exit 1
fi

# check that correct archive has been provided
if [[ ! "$(basename "$1")" == "$CONTROLLER" ]]; then
	echo "First argument must be: $CONTROLLER"
fi

# check if file is provided at user path
if [[ ! -f "$2" ]]; then
	echo "Second argument must be type file: <archive.tar.gz>"
	exit 1
fi

# check that splunk add on archive 
if [[ ! "$(basename "$2")" = "$ADD_ON" ]]; then
	echo "Second argument must be: $ADD_ON"
fi

# -z compress/decompress 
# -x extract
# -v verbose output
# -f read archive from/write archive to specified file
# -C change to specificed directory and write

# extract archives
echo "Extracting splunk archives..."
tar -zxf "$1" -C "$DEFAULT_ROOT"
tar -zxf "$2" -C "$DEFAULT_ROOT"

# check that expected files have been extracted
if [[ ! -d "$DEFAULT_ROOT/$EXTRACTED_CONTROLLER" ]]; then
	echo "Expected folder not found at: $DEFAULT_ROOT/$EXTRACTED_CONTROLLER"
	exit 1
fi

if [[ ! -d "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" ]]; then
	echo "Expected folder not found at: $DEFAULT_ROOT/$EXTRACTED_ADD_ON"
	exit 1
fi

# app config files
SPLUNK_APP_CONFIG_ROOT="$DEFAULT_ROOT/$EXTRACTED_CONTROLLER/etc/apps"

mv "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" "$SPLUNK_APP_CONFIG_ROOT"

mkdir "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"

cp "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/default/inputs.conf" "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"

sed -i s/1/0/g "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"
sed -i s/true/false/g "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"

echo "Splunk installed with add-on for Linux and Unix"
exit 0
