create_splunk_group() {
    # create splunk group if it doesn't exist
    if ! getent group "$SPLUNK_GROUP" > /dev/null 2>&1; then
        log "Creating group: $SPLUNK_GROUP"
        groupadd --system "$SPLUNK_GROUP"
    else
        log "Group '$SPLUNK_GROUP' already exists, skipping..."
    fi
}

create_splunk_user() {
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

