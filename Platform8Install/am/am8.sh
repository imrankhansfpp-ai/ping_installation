#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: am8.sh
# Description: Automates the deployment and configuration of Ping Advanced 
#              Identity Cloud AM 8.0.1 with improved, coloured logging and 
#              centralized configuration.
################################################################################

# ==========================
# Load environment variables
# ==========================
source ./platformconfig.env  # load TOMCAT_DIR, TOMCAT_WEBAPPS_DIR, AMSTER_DIR, etc.

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }

# ==========================
# Dynamic file detection
# ==========================
AM_WAR=$(find "${AM_SOFTWARE_DIR}" -name "AM*.war" -type f | head -n 1)
if [[ -z "$AM_WAR" || ! -f "$AM_WAR" ]]; then
    error "No AM*.war file found in ${AM_SOFTWARE_DIR}"
    exit 1
fi
info "Using AM WAR file: $AM_WAR"

AMSTER_ZIP=$(find "${AMSTER_SOFTWARE_DIR}" -name "Amster-*.zip" -type f | head -n 1)
if [[ -z "$AMSTER_ZIP" || ! -f "$AMSTER_ZIP" ]]; then
    error "No Amster-*.zip file found in ${AMSTER_SOFTWARE_DIR}"
    exit 1
fi
info "Using Amster ZIP file: $AMSTER_ZIP"

# -----------------------------------------------------------------------------
# Helper function to ensure JAVA_HOME is set for Amster operations
# -----------------------------------------------------------------------------
function ensure_java_home() {
    if [[ -z "${JAVA_HOME:-}" ]]; then
        info "JAVA_HOME not set, detecting Java installation..."
        if command -v java >/dev/null 2>&1; then
            export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
            info "JAVA_HOME set to: $JAVA_HOME"
        else
            error "Java not found. Please install Java 21 first."
            return 1
        fi
    fi
    
    # Verify JAVA_HOME is valid
    if [[ ! -f "$JAVA_HOME/bin/java" ]]; then
        error "Invalid JAVA_HOME: $JAVA_HOME"
        return 1
    fi
}

# ========================================
# Function: Ensure Tomcat is running
# ========================================
function start_tomcat_if_not_running() {
    info "Checking if Tomcat is running on port ${TOMCAT_HTTP_PORT}..."
    if netstat -tuln | grep -q "${TOMCAT_HTTP_PORT}.*LISTEN"; then
        success "Tomcat is already running on port ${TOMCAT_HTTP_PORT}."
    else
        info "Tomcat is not running. Starting Tomcat..."
        "${TOMCAT_BIN_DIR}/startup.sh" && success "Tomcat started." || error "Failed to start Tomcat"
        sleep 10
    fi
}

# ========================================
# Function: Clear previous AM deploy
# ========================================
function clear_am() {
    info "Deleting old AM files from ${TOMCAT_WEBAPPS_DIR}..."
    rm -rf "${TOMCAT_WEBAPPS_DIR}/am*" ${AMSTER_DIR} && success "Old AM files removed." || error "Failed to remove old AM files"

    info "Deploying new AM WAR..."
    cp "${AM_WAR}" "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war" && success "New AM WAR copied to webapps." || error "Failed to copy AM WAR"

    # Verify file copy completed successfully by comparing file sizes
    info "Verifying WAR file copy completed successfully..."
    local source_size=$(stat -f%z "${AM_WAR}" 2>/dev/null || stat -c%s "${AM_WAR}" 2>/dev/null)
    local dest_size=$(stat -f%z "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war" 2>/dev/null || stat -c%s "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war" 2>/dev/null)
    
    local retry_count=0
    while [[ "$source_size" != "$dest_size" && $retry_count -lt 30 ]]; do
        info "WAR file copy in progress... source: ${source_size} bytes, dest: ${dest_size} bytes (attempt $((retry_count + 1))/30)"
        sleep 2
        dest_size=$(stat -f%z "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war" 2>/dev/null || stat -c%s "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war" 2>/dev/null)
        ((retry_count++))
    done
    
    if [[ "$source_size" == "$dest_size" ]]; then
        success "WAR file copy verified - file sizes match (${source_size} bytes)"
    else
        error "WAR file copy verification failed - source: ${source_size} bytes, dest: ${dest_size} bytes"
        return 1
    fi

    info "Waiting for AM to deploy..."
    sleep 20
    success "AM deployment delay complete."

    info "Current WARs in Tomcat:"
    ls -lart "${TOMCAT_WEBAPPS_DIR}/"

    info "Verifying Tomcat listening on port ${TOMCAT_HTTP_PORT}..."
    if netstat -tuln | grep -q "${TOMCAT_HTTP_PORT}.*LISTEN"; then
        success "Tomcat is listening on port ${TOMCAT_HTTP_PORT}."
    else
        error "Tomcat is not listening on port ${TOMCAT_HTTP_PORT}."
    fi
}

# ==================================================================================
# Function: setup_amster
# Purpose:  Unzip the Amster tooling from ${AMSTER_ZIP} into ${AMSTER_DIR}
# ==================================================================================
function setup_amster() {
    info "Preparing Amster directory at ${AMSTER_DIR}…"

    info "Unpacking Amster from ${AMSTER_ZIP} to ${AMSTER_SOFTWARE_DIR}…"
    unzip -q -o "${AMSTER_ZIP}" -d "${AMSTER_SOFTWARE_DIR}" \
        && success "Amster unpacked to ${AMSTER_DIR}" \
        || error "Failed to unzip Amster from ${AMSTER_ZIP}"
}

# ========================================
# Function: Run Amster for AM setup
# ========================================
function run_amster() {
    info "Running Amster install ..."
"${AMSTER_DIR}/amster" <<EOF
install-openam \
  --serverUrl ${AM_URL} \
  --adminPwd ${DEFAULT_PASSWORD} \
  --acceptLicense \
  --pwdEncKey ${DS_DEPLOYMENT_ID} \
  --cfgStoreDirMgr 'uid=am-config,ou=admins,ou=am-config' \
  --cfgStoreDirMgrPwd ${DEFAULT_PASSWORD} \
  --cfgStore dirServer \
  --cfgStoreHost ${DS_AMCONFIG_SERVER} \
  --cfgStoreAdminPort ${DS_AMCONFIG_SERVER_ADMIN_CONNECTOR_PORT} \
  --cfgStorePort ${DS_AMCONFIG_SERVER_LDAPS_PORT} \
  --cfgStoreRootSuffix ou=am-config \
  --cfgStoreSsl SSL \
  --userStoreDirMgr 'uid=am-identity-bind-account,ou=admins,${DS_IDREPO_DN}' \
  --userStoreDirMgrPwd ${DEFAULT_PASSWORD} \
  --userStoreHost ${DS_IDREPO_SERVER} \
  --userStoreType LDAPv3ForOpenDS \
  --userStorePort ${DS_IDREPO_SERVER_LDAPS_PORT} \
  --userStoreSsl SSL \
  --userStoreRootSuffix ${DS_IDREPO_DN}

:exit
EOF
}

# ========================================
# Function: Configure CTS via Amster (inline JSON)
# ========================================
function configure_cts() {
    info "Configuring CTS data store via Amster..."

"${AMSTER_DIR}/amster" <<EOF
connect -k ${AM_DIR}/security/keys/amster/amster_rsa ${AM_URL}
update DefaultCtsDataStoreProperties --global --body '{"amconfig.org.forgerock.services.cts.store.common.section":{"org.forgerock.services.cts.store.location":"external","org.forgerock.services.cts.store.root.suffix":"ou=famrecords,ou=openam-session,ou=tokens","org.forgerock.services.cts.store.max.connections":"65","org.forgerock.services.cts.store.page.size":"0","org.forgerock.services.cts.store.vlv.page.size":"1000"},"amconfig.org.forgerock.services.cts.store.external.section":{"org.forgerock.services.cts.store.password":"${DEFAULT_PASSWORD}","org.forgerock.services.cts.store.loginid":"uid=openam_cts,ou=admins,ou=famrecords,ou=openam-session,ou=tokens","org.forgerock.services.cts.store.heartbeat":"10","org.forgerock.services.cts.store.ssl.enabled":"true","org.forgerock.services.cts.store.directory.name":"${DS_CTS_SERVER}:${DS_CTS_SERVER_LDAPS_PORT}","org.forgerock.services.cts.store.affinity.enabled":true}}'
:exit
EOF

    if [ $? -eq 0 ]; then
        success "CTS configuration complete."
    else
        error "CTS configuration failed; check Amster output."
    fi
}

# ========================================
# Function: Restart Tomcat
# ========================================
function restart_am() {
    info "Restarting Tomcat..."
    stop_tomcat
    start_tomcat
}

# ========================================
# Function: stop_tomcat
# Description: Stop Tomcat via systemd, then kill any stragglers
# ========================================
function stop_tomcat() {
    info "Stopping Tomcat via systemctl..."
    if sudo systemctl stop tomcat; then
        success "Tomcat stopped via systemctl."
    else
        warning "systemctl stop tomcat failed; will attempt to kill processes."
    fi
    sleep 5

    info "Checking for any remaining Tomcat processes..."
    local pids
    pids=$(ps -ef | grep '[t]omcat' | awk '{print $2}') || pids=""
    if [[ -n "$pids" ]]; then
        info "Killing stray Tomcat processes: $pids"
        if kill -9 $pids; then
            success "Straggler Tomcat processes terminated."
        else
            error "Failed to kill some Tomcat processes: $pids"
        fi
    else
        success "No leftover Tomcat processes found."
    fi

    info "Tomcat shutdown procedure complete."
}

# ========================================
# Function: start_tomcat
# Description: Start Tomcat via systemd and wait up to ~35 seconds for it to come online
# ========================================
function start_tomcat() {
    info "Starting Tomcat via systemctl..."
    if sudo systemctl start tomcat; then
        success "systemctl start tomcat invoked."
    else
        error "systemctl start tomcat failed."
        return 1
    fi

    # Initial wait before checking
    sleep 15

    local retries=12
    for i in $(seq 1 $retries); do
        if netstat -tuln | grep -q "${TOMCAT_HTTP_PORT}.*LISTEN"; then
            success "Tomcat is listening on port ${TOMCAT_HTTP_PORT}."
            return 0
        else
            warning "Tomcat not started yet, waiting 10 more seconds (attempt ${i}/${retries})..."
            sleep 10
        fi
    done

    error "Tomcat failed to start after $((20 + retries*10)) seconds."
    return 1
}

# ========================================
# Function: Create Alpha Realm
# ========================================
function create_alpha_realm() {
    info "Starting creation of Alpha realm..."

    "${AMSTER_DIR}/amster" <<EOF
connect -k ${AM_DIR}/security/keys/amster/amster_rsa ${AM_URL}
create Realms --global --body '{"_id": "L2FscGhh", "parentPath": "/", "active": true, "name": "alpha", "aliases": []}'
:exit
EOF

    if [ $? -eq 0 ]; then
        success "Alpha realm creation complete."
    else
        error "Alpha realm creation failed; check Amster output."
    fi
}

# ========================================
# Function: Import sample journeys
# ========================================
function import_journeys() {
    info "Starting Amster Import of Journeys located ${AM_JOURNEYS_DIR}"


  "${AMSTER_DIR}/amster" <<EOF
connect -k ${AM_DIR}/security/keys/amster/amster_rsa ${AM_URL}
import-config \
  --path ${AM_JOURNEYS_DIR}

:exit
EOF

    if [ $? -eq 0 ]; then
        success "Journey Import complete."
    else
        error "Journey Import failed; check Amster output."
    fi
}

function deploy_am_envfile(){

    info "Deploying new AM setenv.sh..."
    # Substitute template variables with actual values
    sed -e "s|{{AM_TRUSTSTORE}}|${AM_TRUSTSTORE}|g" \
        -e "s|{{TRUSTSTORE_PASSWORD}}|${TRUSTSTORE_PASSWORD}|g" \
        "${AM_ENV_FILE}" > "${AM_SETENV}" \
        && success "AM setenv.sh file is deployed to ${AM_SETENV}" \
        || error "Failed to copy ${AM_ENV_FILE}"

    success "AM deployment delay complete."
}

# ==========================
# Main execution sequence
# ==========================
ensure_java_home
stop_tomcat
deploy_am_envfile
start_tomcat
clear_am
setup_amster
run_amster
configure_cts
create_alpha_realm
import_journeys
restart_am