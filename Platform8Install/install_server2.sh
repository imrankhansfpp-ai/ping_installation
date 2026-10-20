#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: install_server2.sh
# Description: Installs Server 2 of 2-Server Platform 8 Topology:
#              - Access Management (AM) on Tomcat 10 (512MB)
#              - PingGateway (IG) (512MB)
#              - AM REST Configuration
#              - Platform UI
#              - Test Users
# Target Server RAM: 8 GB (Allocates 512MB heap per component)
################################################################################

# Determine script directory and load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/platformconfig.env"
else
    source ./platformconfig.env
fi

# Logging utility functions
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }

info "================================================================="
info " 🚀 PLATFORM 8 - SERVER 2 INSTALLATION (ACCESS & EDGE TIER)"
info " Components: Tomcat 10 (AM + UI) + PingGateway (IG)"
info " Connected DS Server: ${DS_HOSTNAME}:${DS_LDAPS_PORT}"
info " JVM Heap Target: 512MB per component (Optimal for 8GB RAM host)"
info "================================================================="
echo

# -----------------------------------------------------------------------------
# Function: preflight_checks
# -----------------------------------------------------------------------------
function preflight_checks() {
    info "Running pre-flight checks for Server 2..."
    local missing=0

    local am_war
    am_war=$(find "${AM_SOFTWARE_DIR}" -name "AM*.war" -type f 2>/dev/null | head -n 1) || true
    if [[ -z "$am_war" ]]; then
        error "Missing AM WAR package! Please place AM*.war in: ${AM_SOFTWARE_DIR}/"
        missing=1
    else
        success "Found AM package: $(basename "$am_war")"
    fi

    local amster_zip
    amster_zip=$(find "${AMSTER_SOFTWARE_DIR}" -name "Amster-*.zip" -type f 2>/dev/null | head -n 1) || true
    if [[ -z "$amster_zip" ]]; then
        error "Missing Amster package! Please place Amster-*.zip in: ${AMSTER_SOFTWARE_DIR}/"
        missing=1
    else
        success "Found Amster package: $(basename "$amster_zip")"
    fi

    local ig_zip
    ig_zip=$(find "${IG_SOFTWARE_DIR}" -name "PingGateway*.zip" -type f 2>/dev/null | head -n 1) || true
    if [[ -z "$ig_zip" ]]; then
        error "Missing PingGateway package! Please place PingGateway*.zip in: ${IG_SOFTWARE_DIR}/"
        missing=1
    else
        success "Found PingGateway package: $(basename "$ig_zip")"
    fi

    local ui_zip
    ui_zip=$(find "${UI_SOFTWARE_DIR}" -name "PlatformUI*.zip" -type f 2>/dev/null | head -n 1) || true
    if [[ -z "$ui_zip" ]]; then
        error "Missing Platform UI package! Please place PlatformUI*.zip in: ${UI_SOFTWARE_DIR}/"
        missing=1
    else
        success "Found Platform UI package: $(basename "$ui_zip")"
    fi

    if [[ $missing -ne 0 ]]; then
        error "Pre-flight checks failed. Please place required binaries and rerun."
        exit 1
    fi
    success "Pre-flight binary checks passed"
    echo
}

# -----------------------------------------------------------------------------
# Function: check_server1_connectivity
# -----------------------------------------------------------------------------
function check_server1_connectivity() {
    info "Checking connectivity to Server 1 Directory Server at ${DS_HOSTNAME}:${DS_LDAPS_PORT}..."
    if timeout 5 bash -c "</dev/tcp/${DS_HOSTNAME}/${DS_LDAPS_PORT}" 2>/dev/null; then
        success "Server 1 DS is reachable on port ${DS_LDAPS_PORT} (LDAPS)"
    else
        warning "Could not connect to Server 1 DS at ${DS_HOSTNAME}:${DS_LDAPS_PORT}!"
        warning "Please verify before continuing:"
        warning "  1. Server 1 installation has finished and DS is active (./misc/platform8-control.sh status on Server 1)"
        warning "  2. /etc/hosts on this server maps '${DS_HOSTNAME}' to Server 1's IP"
        warning "  3. Firewall / Security Groups allow inbound traffic from Server 2 on port ${DS_LDAPS_PORT} and ${DS_ADMIN_CONNECTOR_PORT}"
        echo
        read -p "Do you want to proceed anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation aborted by user"
            exit 1
        fi
    fi
    echo
}

# -----------------------------------------------------------------------------
# Function: cleanup_am
# -----------------------------------------------------------------------------
function cleanup_am() {
    info "Cleaning up existing AM installation"
    rm -rf "$AM_DIR" "$AM_CFG_DIR" "$TOMCAT_AM_WAR"
    success "Old AM files removed"
}

# -----------------------------------------------------------------------------
# Function: ensure_ds_cert_imported
# -----------------------------------------------------------------------------
function ensure_ds_cert_imported() {
    info "Resolving Server 1 DS CA certificate..."
    sudo mkdir -p "${AM_TRUSTSTORE_FOLDER}"
    sudo chown -R "${INSTALL_USER}:${INSTALL_USER}" "${BASE_INSTALL_DIR}/${AM_CONTEXT}" 2>/dev/null || true

    local cert_candidates=(
        "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
        "${SCRIPT_DIR}/misc/keys/ds-ca-cert.pem"
        "${SCRIPT_DIR}/ds-ca-cert.pem"
        "/tmp/ds-ca-cert.pem"
    )

    local found_cert=""
    for candidate in "${cert_candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            found_cert="$candidate"
            break
        fi
    done

    if [[ -z "$found_cert" ]]; then
        error "================================================================="
        error "❌ Server 1 DS CA Certificate (ds-ca-cert.pem) was NOT found!"
        error "================================================================="
        info "To fix this, run ONE of the following commands from Server 1:"
        info "  scp ./misc/keys/ds-ca-cert.pem ${INSTALL_USER}@$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<server2-ip>'):${SCRIPT_DIR}/misc/keys/"
        info "  OR:"
        info "  scp ${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem ${INSTALL_USER}@$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<server2-ip>'):${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
        echo
        error "After copying the certificate, rerun ./install_server2.sh"
        exit 1
    fi

    info "Found DS CA certificate at: $found_cert"
    if [[ "$found_cert" != "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem" ]]; then
        cp -f "$found_cert" "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
        success "Copied certificate to ${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
    fi

    if [[ ! -f "${AM_TRUSTSTORE}" ]]; then
        info "Initializing truststore from system Java cacerts..."
        local java_bin
        java_bin=$(readlink -f "$(which java 2>/dev/null || which javac 2>/dev/null)" || true)
        local detected_cacerts=""
        if [[ -n "$java_bin" && -f "$java_bin" ]]; then
            detected_cacerts="$(dirname "$(dirname "$java_bin")")/lib/security/cacerts"
        fi
        local java_cacerts="${jvm_cacerts:-${detected_cacerts}}"
        if [[ -f "$java_cacerts" ]]; then
            sudo cp "$java_cacerts" "${AM_TRUSTSTORE}"
            sudo chown "${INSTALL_USER}:${INSTALL_USER}" "${AM_TRUSTSTORE}"
            sudo chmod 644 "${AM_TRUSTSTORE}"
            success "Truststore initialized from system Java cacerts"
        else
            error "Could not find system Java cacerts at: $java_cacerts"
            exit 1
        fi
    fi

    info "Importing ds-ca-cert.pem into AM truststore..."
    keytool -delete -alias "ds-ca-cert" -keystore "${AM_TRUSTSTORE}" -storepass "${TRUSTSTORE_PASSWORD}" 2>/dev/null || true
    keytool -importcert -file "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem" \
        -keystore "${AM_TRUSTSTORE}" -storepass "${TRUSTSTORE_PASSWORD}" \
        -alias "ds-ca-cert" -noprompt || true
    success "DS CA cert registered in truststore at ${AM_TRUSTSTORE}"

    # Export truststore properties for all subsequent child scripts (Amster, etc.)
    export JAVA_OPTS="${JAVA_OPTS:-} -Djavax.net.ssl.trustStore=${AM_TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}"
    export AMSTER_OPTS="${AMSTER_OPTS:-} -Djavax.net.ssl.trustStore=${AM_TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}"
}

# -----------------------------------------------------------------------------
# Function: create_test_users
# -----------------------------------------------------------------------------
function create_test_users() {
    local count="${TEST_USER_COUNT:-0}"
    if [[ "${INSTALL_TEST_USERS:-true}" != "true" || "$count" -le 0 ]]; then
        info "Skipping test user creation"
        return 0
    fi

    info "Creating ${count} test users via IDM managed/user"
    local realm="${REALM_NAME:-alpha}"
    local am_token_url="${AM_URL}/oauth2/realms/root/realms/${realm}/access_token"
    local idm_url="http://${IDM_HOSTNAME}:${BOOT_PORT_HTTP}/openidm/managed/user?_action=create"
    local pw="${TEST_USER_PASSWORD:-!@34QWer}"
    local created=0 failed=0

    local idm_provisioning_secret="${IDM_PROVISIONING_SECRET:-openidm}"
    local token_response
    token_response=$(curl -sk -X POST \
        -u "idm-provisioning:${idm_provisioning_secret}" \
        -d "grant_type=client_credentials&scope=fr:idm:*" \
        "$am_token_url" 2>/dev/null) || true

    local access_token=""
    if command -v python3 >/dev/null 2>&1; then
        access_token=$(echo "$token_response" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)
    elif command -v jq >/dev/null 2>&1; then
        access_token=$(echo "$token_response" | jq -r '.access_token // empty' 2>/dev/null || true)
    else
        access_token=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
    fi

    if [[ -z "$access_token" ]]; then
        warning "Could not obtain idm-provisioning token — skipping test user creation"
        return 0
    fi

    for i in $(seq 1 "$count"); do
        local body
        body=$(printf '{"userName":"testuser%s","givenName":"Test","sn":"User%s","mail":"testuser%s@example.com","password":"%s","accountStatus":"active","preferences":{"updates":false,"marketing":false}}' "$i" "$i" "$i" "$pw")
        local response http
        response=$(curl -sk -o - -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${access_token}" \
            -d "$body" \
            "$idm_url" 2>/dev/null) || true
        http=$(echo "$response" | tail -1)
        local content; content=$(echo "$response" | sed '$d')
        if [[ "$http" == "201" ]] && echo "$content" | grep -q '"_id"'; then
            info "  + testuser${i} created"
            created=$((created+1))
        elif echo "$content" | grep -qiE 'conflict|already exists|VALID_USERNAME'; then
            info "  · testuser${i} already exists"
            created=$((created+1))
        else
            warning "  ! testuser${i} failed (HTTP $http)"
            failed=$((failed+1))
        fi
    done
    success "Test users processed: ${created} ready"
}

# -----------------------------------------------------------------------------
# Configuration Mode Choice
# -----------------------------------------------------------------------------
preflight_checks
check_server1_connectivity

echo "Do you want to install AM with File Based Config (FBC) or DS based Config"
read -p "Enter 1 for File Based Config (FBC) [Recommended], 2 for DS based Config (Default: 1): " am_config_choice
am_config_choice="${am_config_choice:-1}"
if [[ "$am_config_choice" == "2" ]]; then
    am_config_type="DS"
else
    am_config_type="FBC"
fi

# -----------------------------------------------------------------------------
# STEP 1: Cleanup previous AM
# -----------------------------------------------------------------------------
info "────────── 🧹 STEP 1: Cleanup previous AM ──────────"
cleanup_am
ensure_ds_cert_imported
success "✅ Step 1 complete: AM cleaned up and truststore prepared"
echo

# -----------------------------------------------------------------------------
# STEP 2: Deploy AM (Tomcat 10 with 512MB RAM)
# -----------------------------------------------------------------------------
info "────────── ⚙️ STEP 2: Deploy AM (${am_config_type} mode, 512MB) ──────────"
if [[ "$am_config_type" == "FBC" ]]; then
    bash "$AM_FBC_SCRIPT" && success "✅ Step 2 complete: AM deployed with FBC"
else
    bash "$AM_SCRIPT" && success "✅ Step 2 complete: AM deployed with DS"
fi
echo

# -----------------------------------------------------------------------------
# STEP 3: Deploy IG (PingGateway with 512MB RAM)
# -----------------------------------------------------------------------------
info "────────── 🔐 STEP 3: Deploy IG (512MB) ──────────"
bash "$IG_SCRIPT" && success "✅ Step 3 complete: IG deployed"
echo

# -----------------------------------------------------------------------------
# STEP 4: Configure AM via REST
# -----------------------------------------------------------------------------
info "────────── 🔐 STEP 4: Configure AM via REST ──────────"
bash "$AM_REST_SCRIPT" && success "✅ Step 4 complete: AM Configured"
echo

# -----------------------------------------------------------------------------
# STEP 5: Deploy Platform UI
# -----------------------------------------------------------------------------
info "────────── 🖥️ STEP 5: Deploy Platform UI ──────────"
bash "$UI_SCRIPT" && success "✅ Step 5 complete: UI deployed"
echo

# -----------------------------------------------------------------------------
# STEP 6: Create test users
# -----------------------------------------------------------------------------
info "────────── 👥 STEP 6: Create test users ──────────"
create_test_users || warning "Test user creation finished with warnings"
echo

success "================================================================="
success "🎉 SERVER 2 & PLATFORM 8 INSTALLATION COMPLETED SUCCESSFULLY!"
success "   Access the Platform Gateway: https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}"
success "================================================================="
