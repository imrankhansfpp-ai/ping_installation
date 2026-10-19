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

# Load central configuration
source ./platformconfig.env

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
    info "Checking for Server 1 DS CA certificate in ${AM_TRUSTSTORE_FOLDER}..."
    mkdir -p "${AM_TRUSTSTORE_FOLDER}"
    if [[ ! -f "${AM_TRUSTSTORE}" ]]; then
        info "Initializing truststore from system Java cacerts..."
        local java_cacerts
        java_cacerts="${jvm_cacerts:-$(dirname $(dirname $(readlink -f $(which javac))))/lib/security/cacerts}"
        sudo cp "$java_cacerts" "${AM_TRUSTSTORE}"
        sudo chown "${INSTALL_USER}:${INSTALL_USER}" "${AM_TRUSTSTORE}"
        sudo chmod 644 "${AM_TRUSTSTORE}"
    fi

    local ds_cert="${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
    if [[ -f "$ds_cert" ]]; then
        info "Importing ds-ca-cert.pem into AM truststore..."
        keytool -importcert -file "$ds_cert" \
            -keystore "${AM_TRUSTSTORE}" -storepass "${TRUSTSTORE_PASSWORD}" \
            -alias "ds-ca-cert" -noprompt || true
        success "DS CA cert registered in truststore"
    else
        warning "ds-ca-cert.pem not found in ${AM_TRUSTSTORE_FOLDER}!"
        warning "Ensure you copied ds-ca-cert.pem from Server 1 so LDAPS trust succeeds."
    fi
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
    local access_token
    access_token=$(echo "$token_response" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null) || true

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
echo "Do you want to install AM with File Based Config (FBC) or DS based Config"
read -p "Enter 1 for File Based Config (FBC) [Recommended], 2 for DS based Config: " am_config_choice
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
