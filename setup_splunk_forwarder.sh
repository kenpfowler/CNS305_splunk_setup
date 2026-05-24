#!/bin/bash
# =============================================================
# AUTHOR:        Ken Fowler
# COURSE:        SEC320
# LAST MODIFIED: May 24, 2026
# -------------------------------------------------------------
# DESCRIPTION:
#   Installs and configures Splunk Universal Forwarder
#   with the Unix/Linux add-on. Sets up splunk service
#   account, systemd boot-start, forwarding to controller,
#   and /var/log monitoring.
# -------------------------------------------------------------
# USAGE:
#   sudo ./setup_splunk_forwarder.sh <splunkforwarder.tar.gz> \
#        <addon.tar.gz> <controller_ip>
# =============================================================
set -euo pipefail

# required archives
readonly FORWARDER="splunkforwarder-8.2.4-87e2dda940d1-Linux-x86_64.tgz"
readonly ADD_ON="splunk-add-on-for-unix-and-linux_870.tgz"

# expected extractions
readonly EXTRACTED_FORWARDER="splunkforwarder"
readonly EXTRACTED_ADD_ON="Splunk_TA_nix"

# default install root
readonly DEFAULT_ROOT="/opt"

# splunk service user
readonly SPLUNK_USER="splunk"
readonly SPLUNK_GROUP="splunk"
readonly SPLUNK_HOME="$DEFAULT_ROOT/$EXTRACTED_FORWARDER"

log() {
    echo "[splunk_installer] $1"
}

# run script as root
validate_input() {
    if [[ "$EUID" -ne 0 ]]; then
        log "Please run as root (e.g., sudo $0)"
        exit 1
    fi

    # check that 3 arguments are provided
    if [[ $# -ne 3 ]]; then
        log "Usage: $0 <$FORWARDER> <$ADD_ON> <controller_ip>"
        exit 1
    fi

    # validate forwarder archive
    if [[ ! -f "$1" ]]; then
        log "First argument must be a file: <$FORWARDER>"
        exit 1
    fi

    if [[ "$(basename "$1")" != "$FORWARDER" ]]; then
        log "First argument must be: $FORWARDER"
        exit 1
    fi

    # validate add-on archive
    if [[ ! -f "$2" ]]; then
        log "Second argument must be a file: <$ADD_ON>"
        exit 1
    fi

    if [[ "$(basename "$2")" != "$ADD_ON" ]]; then
        log "Second argument must be: $ADD_ON"
        exit 1
    fi

    # validate controller IP
    CONTROLLER_IP="$3"

    if [[ ! "$CONTROLLER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "Third argument must be a valid IP address: <controller_ip>"
        exit 1
    fi

    # prompt user for splunk admin password
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

extract_archive() {
    # extract archives
    log "Extracting archives..."
    tar -zxf "$1" -C "$DEFAULT_ROOT"
    tar -zxf "$2" -C "$DEFAULT_ROOT"

    # validate extraction
    if [[ ! -d "$DEFAULT_ROOT/$EXTRACTED_FORWARDER" ]]; then
        log "Expected folder not found at: $DEFAULT_ROOT/$EXTRACTED_FORWARDER"
        exit 1
    fi
    if [[ ! -d "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" ]]; then
        log "Expected folder not found at: $DEFAULT_ROOT/$EXTRACTED_ADD_ON"
        exit 1
    fi
}

configure_ownership() {
    log "Setting ownership of $SPLUNK_HOME to $SPLUNK_USER:$SPLUNK_GROUP..."
    chown -R "$SPLUNK_USER":"$SPLUNK_GROUP" "$SPLUNK_HOME"
}

configure_addon() {
    # configure add-on
    log "Configuring add-on..."
    local SPLUNK_APP_CONFIG_ROOT="$SPLUNK_HOME/etc/apps"
    
    if [[ ! -d "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON" ]]; then
        mv "$DEFAULT_ROOT/$EXTRACTED_ADD_ON" "$SPLUNK_APP_CONFIG_ROOT"
    fi

    mkdir -p "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"
    cp "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/default/inputs.conf" "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local"
    sed -i 's/^disabled = 1/disabled = 0/g' "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"
    sed -i 's/^disabled = true/disabled = false/g' "$SPLUNK_APP_CONFIG_ROOT/$EXTRACTED_ADD_ON/local/inputs.conf"
}

configure_admin_account() {
    # set admin credentials
    log "Configuring admin credentials..."
    mkdir -p "$SPLUNK_HOME/etc/system/local"
    cat > "$SPLUNK_HOME/etc/system/local/user-seed.conf" << EOF
    [user_info]
    USERNAME = admin
    PASSWORD = $SPLUNK_ADMIN_PASSWORD
EOF
}

enable_boot_start() {
    # enable boot-start
    log "Enabling boot-start..."
    "$SPLUNK_HOME/bin/splunk" enable boot-start \
    -systemd-managed 1 \
    -user "$SPLUNK_USER" \
    --accept-license \
    --answer-yes \
    --no-prompt

    # patch cgroup lines from service file
    log "Patching SplunkForwarder.service..."
    sed -i '/chown -R.*cgroup/d' /etc/systemd/system/SplunkForwarder.service
}

enable_monitor() {
    # add log monitor
    # check if monitor already exists before adding
    if sudo -u splunk "$SPLUNK_HOME/bin/splunk" list monitor \
        -auth "admin:$SPLUNK_ADMIN_PASSWORD" | grep -q "/var/log"; then
        log "Monitor for /var/log already exists, skipping..."
    else
        log "Adding /var/log monitor..."
        sudo -u splunk "$SPLUNK_HOME/bin/splunk" add monitor /var/log/ \
        -auth "admin:$SPLUNK_ADMIN_PASSWORD"
    fi
}

configure_acl() {
# install acl package if not present
if ! command -v setfacl > /dev/null 2>&1; then
    log "Installing acl package..."
    dnf install -y acl
fi

# Apply ACL to current and any existing rotated files
log "Setting ACL on /var/log/secure and rotated files..."
for log in /var/log/secure /var/log/secure-*; do
    if [[ -f "$log" ]]; then
        setfacl -m u:"$SPLUNK_USER":r "$log"
    fi
done

# Persist ACL across log rotations
log "Configuring logrotate to persist ACL..."
# Instead of sed, create a dedicated logrotate drop-in file
cat > /etc/logrotate.d/splunk-secure-acl << EOF
/var/log/secure {
    postrotate
        /usr/bin/setfacl -m u:${SPLUNK_USER}:r /var/log/secure 2>/dev/null || true
    endscript
}
EOF

# verify splunk user can read the log
if sudo -u "$SPLUNK_USER" test -r /var/log/secure; then
    log "ACL verified - splunk user can read /var/log/secure"
else
    log "Error: splunk user cannot read /var/log/secure"
    exit 1
fi
}

configure_forwarding_to_controller() {
    # configure forwarding to controller
    log "Configuring forwarding to controller at $CONTROLLER_IP..."
    sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" add forward-server "$CONTROLLER_IP:9997" \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD"
}

configure_deploy_poll() {
    # configure deployment server poll
    log "Configuring deployment poll..."
    sudo -u "$SPLUNK_USER" "$SPLUNK_HOME/bin/splunk" set deploy-poll "$CONTROLLER_IP:8089" \
    -auth "admin:$SPLUNK_ADMIN_PASSWORD"
}

configure_firewall() {
    # open firewall ports
    log "Configuring firewall..."
    firewall-cmd --add-port=9997/tcp --zone=public --permanent
    firewall-cmd --add-port=8089/tcp --zone=public --permanent
    firewall-cmd --reload
}

start_splunk_forwarder() {
    # start forwarder
    log "Starting Splunk forwarder..."
    systemctl daemon-reload
    systemctl start SplunkForwarder.service
}

reload_splunk_forwarder() {
    systemctl restart SplunkForwarder.service
    systemctl status SplunkForwarder.service --no-pager
    log "Login with username: admin"
    log "Splunk forwarder installed and configured successfully"
}

main() {
    validate_input "$@"
    create_splunk_user
    extract_archive "$@"
    configure_ownership
    configure_addon
    configure_admin_account
    configure_ownership
    enable_boot_start
    start_splunk_forwarder
    configure_forwarding_to_controller
    configure_deploy_poll
    enable_monitor
    configure_acl
    configure_firewall
    reload_splunk_forwarder
}

main "$@"

exit 0
