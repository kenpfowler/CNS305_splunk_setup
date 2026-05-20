#!/bin/bash
# =============================================================
# AUTHOR:        Ken Fowler
# COURSE:        SEC320
# LAST MODIFIED: May 20, 2026
# -------------------------------------------------------------
# DESCRIPTION:
#   Installs and configures Splunk Enterprise controller
#   with the Unix/Linux add-on. Sets up splunk service
#   account, systemd boot-start, and firewall rules.
# -------------------------------------------------------------
# USAGE:
#   sudo ./setup_splunk_controller.sh <splunk.tar.gz> \
#        <addon.tar.gz> <admin_password>
# =============================================================

# -e exit on any error
# -u exit on unassigned variable
# -o exit on pipeline failure
set -euo pipefail

# required archives
CONTROLLER="splunk-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
ADD_ON="splunk-add-on-for-unix-and-linux_870.tgz"

# expected extractions
EXTRACTED_ADD_ON="Splunk_TA_nix"
EXTRACTED_CONTROLLER="splunk"

# default root splunk enterprise
DEFAULT_ROOT="/opt"

# splunk service user
SPLUNK_USER="splunk"
SPLUNK_GROUP="splunk"
SPLUNK_HOME="$DEFAULT_ROOT/$EXTRACTED_CONTROLLER"

# run script as root user
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (e.g., sudo $0)"
    exit 1
fi

# check that three arguments are provided
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
if [[ "$(basename "$1")" != "$CONTROLLER" ]]; then
    echo "First argument must be: $CONTROLLER"
    exit 1
fi

# check if file is provided at user path
if [[ ! -f "$2" ]]; then
    echo "Second argument must be type file: <archive.tar.gz>"
    exit 1
fi

# check that splunk add on archive
if [[ "$(basename "$2")" != "$ADD_ON" ]]; then
    echo "Second argument must be: $ADD_ON"
    exit 1
fi

# Replace the $3 argument approach with an interactive prompt
read -r -s -p "Enter Splunk admin password: " SPLUNK_ADMIN_PASSWORD
echo
read -r -s -p "Confirm Splunk admin password: " SPLUNK_ADMIN_PASSWORD_CONFIRM
echo

# Confirm passwords match
if [[ "$SPLUNK_ADMIN_PASSWORD" != "$SPLUNK_ADMIN_PASSWORD_CONFIRM" ]]; then
    echo "Error: Passwords do not match"
    exit 1
fi

# Password strength check
if [[ ${#SPLUNK_ADMIN_PASSWORD} -lt 8 ]]; then
    echo "Error: Password must be at least 8 characters"
    exit 1
fi

# create splunk group if it doesn't exist
if ! getent group "$SPLUNK_GROUP" > /dev/null 2>&1; then
    echo "Creating group: $SPLUNK_GROUP"
    groupadd --system "$SPLUNK_GROUP"
else
    echo "Group '$SPLUNK_GROUP' already exists, skipping..."
fi

# create splunk user if it doesn't exist
if ! getent passwd "$SPLUNK_USER" > /dev/null 2>&1; then
    echo "Creating user: $SPLUNK_USER"
    useradd \
        --system \
        --gid "$SPLUNK_GROUP" \
        --home-dir "$SPLUNK_HOME" \
        --no-create-home \
        --shell /sbin/nologin \
        --comment "Splunk service account" \
        "$SPLUNK_USER"
else
    echo "User '$SPLUNK_USER' already exists, skipping..."
fi

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

# set ownership before any further operations
echo "Setting ownership of $SPLUNK_HOME to $SPLUNK_USER:$SPLUNK_GROUP..."
chown -R "$SPLUNK_USER":"$SPLUNK_GROUP" "$SPLUNK_HOME"

# app config files
SPLUNK_APP_CONFIG_ROOT="$SPLUNK_HOME/etc/apps"
mv "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" "$SPLUNK_APP_CONFIG_ROOT"
mkdir "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"
cp "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/default/inputs.conf" "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"
sed -i s/1/0/g "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"
sed -i s/true/false/g "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"

# set initial admin credentials via user-seed.conf
# splunk reads this on first start, creates the admin user, then deletes the file
echo "Configuring admin credentials..."
mkdir -p "$SPLUNK_HOME/etc/system/local"
cat > "$SPLUNK_HOME/etc/system/local/user-seed.conf" << EOF
[user_info]
USERNAME = admin
PASSWORD = $SPLUNK_ADMIN_PASSWORD
EOF

# fix ownership after all file operations
chown -R "$SPLUNK_USER":"$SPLUNK_GROUP" "$SPLUNK_HOME"

# enable boot-start under splunk user with systemd
echo "Enabling Splunk boot-start..."
"$SPLUNK_HOME/bin/splunk" enable boot-start \
    -systemd-managed 1 \
    -user "$SPLUNK_USER" \
    --accept-license \
    --answer-yes \
    --no-prompt

# remove problematic cgroup chown lines from service file
echo "Patching Splunkd.service..."
sed -i '/chown -R.*cgroup/d' /etc/systemd/system/Splunkd.service

# enable receiving from forwarders on port 9997
echo "Enabling Splunk receiver on port 9997..."
sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" enable listen 9997 \
    --accept-license \
    --answer-yes \
    --no-prompt \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD"

# open firewall ports
echo "Configuring firewall..."
firewall-cmd --add-port=8000/tcp --zone=public --permanent  # web UI
firewall-cmd --add-port=8089/tcp --zone=public --permanent  # management
firewall-cmd --add-port=9997/tcp --zone=public --permanent  # forwarder receiving
firewall-cmd --reload

# reload systemd and start splunk
echo "Starting Splunk..."
systemctl daemon-reload
systemctl start Splunkd.service
systemctl status Splunkd.service --no-pager

echo "Splunk controller installed successfully with add-on for Linux and Unix"
echo "Web UI available at: http://$(hostname -I | awk '{print $1}'):8000"
echo "Login with username: admin"
exit 0
