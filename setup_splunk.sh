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
#        <addon.tar.gz>
# =============================================================

# -e exit on any error
# -u exit on unassigned variable
# -o exit on pipeline failure
set -euo pipefail

# required archives
readonly CONTROLLER="splunk-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
readonly ADD_ON="splunk-add-on-for-unix-and-linux_870.tgz"

# expected extractions
readonly EXTRACTED_ADD_ON="Splunk_TA_nix"
readonly EXTRACTED_CONTROLLER="splunk"

# default root for optional software (CentOS)
readonly DEFAULT_ROOT="/opt"

# splunk service user
readonly SPLUNK_USER="splunk"
readonly SPLUNK_GROUP="splunk"
readonly SPLUNK_HOME="$DEFAULT_ROOT/$EXTRACTED_CONTROLLER"

log() {
    echo "[splunk_installer] $1"
}

validate_arguments() {
    # run script as root user
    if [[ "$EUID" -ne 0 ]]; then
        log "Please run as root (e.g., sudo $0)"
        exit 1
    fi

    # check that two arguments are provided
    if [[ $# -ne 2 ]]; then
        log "Usage: $0 <splunk.tar.gz> <splunk_add_on.tar.gz>"
        exit 1
    fi

    # check if file exists at user path
    if [[ ! -f "$1" ]]; then
        log "First argument must be type file: <archive.tar.gz>"
        exit 1
    fi

    # check that correct archive has been provided
    if [[ "$(basename "$1")" != "$CONTROLLER" ]]; then
        log "First argument must be: $CONTROLLER"
        exit 1
    fi

    # check if file is provided at user path
    if [[ ! -f "$2" ]]; then
        log "Second argument must be type file: <archive.tar.gz>"
        exit 1
    fi

    # check that splunk add on archive
    if [[ "$(basename "$2")" != "$ADD_ON" ]]; then
        log "Second argument must be: $ADD_ON"
        exit 1
    fi

    # Prompt user for splunk admin account password
    read -r -s -p "Enter Splunk admin password: " SPLUNK_ADMIN_PASSWORD
    echo
    read -r -s -p "Confirm Splunk admin password: " SPLUNK_ADMIN_PASSWORD_CONFIRM
    echo

    # Confirm passwords match
    if [[ "$SPLUNK_ADMIN_PASSWORD" != "$SPLUNK_ADMIN_PASSWORD_CONFIRM" ]]; then
        log "Error: Passwords do not match"
        exit 1
    fi

    # Password strength check
    if [[ ${#SPLUNK_ADMIN_PASSWORD} -lt 8 ]]; then
        log "Error: Password must be at least 8 characters"
        exit 1
    fi
}

create_splunk_user() {
    # create splunk group if it doesn't exist
    if ! getent group "$SPLUNK_GROUP" > /dev/null 2>&1; then
        log "Creating group: $SPLUNK_GROUP"
        groupadd --system "$SPLUNK_GROUP"
    else
        log "Group '$SPLUNK_GROUP' already exists, skipping..."
    fi

    # create splunk user if it doesn't exist
    if ! getent passwd "$SPLUNK_USER" > /dev/null 2>&1; then
        log "Creating user: $SPLUNK_USER"
        useradd \
        --system \
        --gid "$SPLUNK_GROUP" \
        --home-dir "$SPLUNK_HOME" \
        --no-create-home \
        --shell /sbin/nologin \
        --comment "Splunk service account" \
        "$SPLUNK_USER"
    else
        log "User '$SPLUNK_USER' already exists, skipping..."
    fi
}

extract_archives() {
    log "Extracting splunk archives..."
    tar -zxf "$1" -C "$DEFAULT_ROOT"
    tar -zxf "$2" -C "$DEFAULT_ROOT"

    # check that expected files have been extracted
    if [[ ! -d "$DEFAULT_ROOT/$EXTRACTED_CONTROLLER" ]]; then
        log "Expected folder not found at: $DEFAULT_ROOT/$EXTRACTED_CONTROLLER"
        exit 1
    fi

    if [[ ! -d "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" ]]; then
        log "Expected folder not found at: $DEFAULT_ROOT/$EXTRACTED_ADD_ON"
        exit 1
    fi
}

configure_addon() {
    # set ownership before any further operations
    log "Setting ownership of $SPLUNK_HOME to $SPLUNK_USER:$SPLUNK_GROUP..."
    chown -R "$SPLUNK_USER":"$SPLUNK_GROUP" "$SPLUNK_HOME"

    # app config files
    local SPLUNK_APP_CONFIG_ROOT="$SPLUNK_HOME/etc/apps"
    
    if [[ ! -d $SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON ]]; then
        mv "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" "$SPLUNK_APP_CONFIG_ROOT"
    fi
    
    mkdir -p "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"
    cp "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/default/inputs.conf" "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"
    # FIXME: use a better targeted substituion pattern
    sed -i s/1/0/g "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"
    sed -i s/true/false/g "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"
}

configure_admin_account() {
# set initial admin credentials via user-seed.conf
# splunk reads this on first start, creates the admin user, then deletes the file
log "Configuring admin credentials..."
mkdir -p "$SPLUNK_HOME/etc/system/local"
cat > "$SPLUNK_HOME/etc/system/local/user-seed.conf" << EOF
[user_info]
USERNAME = admin
PASSWORD = $SPLUNK_ADMIN_PASSWORD
EOF
}

fix_ownership() {
    # fix ownership after all file operations
    chown -R "$SPLUNK_USER":"$SPLUNK_GROUP" "$SPLUNK_HOME"
}

enable_boot_start() {
    # enable boot-start under splunk user with systemd
    log "Enabling Splunk boot-start..."
    "$SPLUNK_HOME/bin/splunk" enable boot-start \
    -systemd-managed 1 \
    -user "$SPLUNK_USER" \
    --accept-license \
    --answer-yes \
    --no-prompt

    # remove problematic cgroup chown lines from service file
    log "Patching Splunkd.service..."
    sed -i '/chown -R.*cgroup/d' /etc/systemd/system/Splunkd.service
}

enable_listen() {
    # enable receiving from forwarders on port 9997
    log "Enabling Splunk receiver on port 9997..."
    sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" enable listen 9997 \
    --accept-license \
    --answer-yes \
    --no-prompt \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD"
}

configure_firewall_rules() {
    # open firewall ports
    log "Configuring firewall..."
    firewall-cmd --add-port=8000/tcp --zone=public --permanent  # web UI
    firewall-cmd --add-port=8089/tcp --zone=public --permanent  # management
    firewall-cmd --add-port=9997/tcp --zone=public --permanent  # forwarder receiving
    firewall-cmd --reload
}

start_splunk() {
    # reload systemd and start splunk
    log "Starting Splunk..."
    systemctl daemon-reload
    systemctl start Splunkd.service
    systemctl status Splunkd.service --no-pager

    log "Splunk controller installed successfully with add-on for Linux and Unix"
    log "Web UI available at: http://$(hostname -I | awk '{print $1}'):8000"
    log "Login with username: admin"
}

# call required functions for installation in sequence
main() {
    validate_arguments "$@"
    create_splunk_user
    extract_archives "$@"
    configure_addon
    configure_admin_account
    fix_ownership
    enable_boot_start
    enable_listen
    configure_firewall_rules
    start_splunk
}

main "$@"

exit 0
