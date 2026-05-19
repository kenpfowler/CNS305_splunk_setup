#!/bin/bash

# exit on any error
set -e

# if the number of arguments is less than 2, stop the script
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <archive1.tar.gz> <archive2.tar.gz>"
    exit 1
fi

# required archives
controller="splunk-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
agent="splunkforwarder-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
add_on="splunk-add-on-for-unix-and-linux_870.tgz"

# expected extractions
extracted_add_on="Splunk_TA_nix"
extracted_forwarder="splunkforwarder"
extracted_controller="splunk"

# default root splunk
default_root="$HOME/opt"

# check if splunk archive exists
if [ ! -f "$1" ]; then  
	echo "First argument must be type file: <archive.tar.gz>"
	exit 1
fi

# check if splunk add-on archive exists
if [ ! -f "$2" ]; then
	echo "Second argument must be type file: <archive.tar.gz>"
	exit 1
fi

# -z compress/decompress 
# -x extract
# -v verbose output
# -f read archive from/write archive to specified file
# -C change to specificed directory and write

# extract archives
tar -zxvf "$1" -C "$default_root"
tar -zxvf "$2" -C "$default_root"

# check that expected files have been extracted
if [ ! -f "$default_root/$extracted_controller" ]; then
	echo "Expected file not found at: $default_root/$extracted_controller"
	exit 1
fi

if [ ! -f "$default_root/$extracted_add_on" ] then
	echo "Expected file not found at: $default_root/$extracted_add_on"
	exit 1
fi


