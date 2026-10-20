#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: install_platform8.sh
# Description: Orchestrates full Platform 8 installation including:
#              - Directory Services (DS)
#              - Access Management (AM) with File-Based Config (FBC) or DS-based Config
#              - Identity Management (IDM)
#              - PingGateway (IG) if desired
################################################################################

# Determine script directory and load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/platformconfig.env"
else
    source ./platformconfig.env
fi

# -----------------------------------------------------------------------------
# Logging utility functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }

# -----------------------------------------------------------------------------
# Function: stop_idm_if_running
# Description: Detects any running OpenIDM process and attempts a graceful shutdown.
#              Falls back to forceful kill if shutdown script fails.
# -----------------------------------------------------------------------------
function stop_idm_if_running() {
    info "Checking for running IDM processes..."
    local pid
    pid=$(pgrep -f 'openidm' || true)
    if [[ -n "$pid" ]]; then
        info "Found IDM (PID:$pid), invoking shutdown"
        if [[ -x "$IDM_EXTRACT_DIR/shutdown.sh" ]] && "$IDM_EXTRACT_DIR/shutdown.sh"; then
            success "IDM stopped gracefully"
        else
            warning "Graceful shutdown failed, killing PID $pid"
            kill -9 "$pid" || true
            success "IDM process killed"
        fi
        sleep 5
    else
        info "No IDM process detected"
    fi
}

# -----------------------------------------------------------------------------
# Function: cleanup_am
# Description: Removes previous Access Management installation artifacts and WAR file.
# -----------------------------------------------------------------------------
function cleanup_am() {
    info "Cleaning up existing AM installation"
    rm -rf "$AM_DIR" "$AM_CFG_DIR" "$TOMCAT_AM_WAR"
    success "Old AM files removed"
}

# -----------------------------------------------------------------------------
# Function: configure_ds
# Description: Executes the DS configuration script (ds8.sh) to set up DS instances.
# -----------------------------------------------------------------------------
function configure_ds() {
    info "Configuring Directory Services (DS)"
    if bash "$DS_SCRIPT"; then
        success "DS configuration completed"
    else
        error "DS configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: configure_am
# Description: Executes the AM configuration script (am8.sh) for standard AM setup.
# -----------------------------------------------------------------------------
function configure_am() {
    info "Configuring Access Management (AM)"
    if bash "$AM_SCRIPT"; then
        success "AM configuration completed"
    else
        error "AM configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: configure_am_fbc
# Description: Executes the AM configuration script with File-Based Config (FBC).
# -----------------------------------------------------------------------------
function configure_am_fbc() {
    info "Configuring Access Management (AM) - FBC mode"
    if bash "$AM_FBC_SCRIPT"; then
        success "AM FBC configuration completed"
    else
        error "AM FBC configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: configure_idm
# Description: Executes the IDM configuration script (idm8.sh) to set up OpenIDM.
# -----------------------------------------------------------------------------
function configure_idm() {
    info "Configuring Identity Management (IDM)"
    if bash "$IDM_SCRIPT"; then
        success "IDM configuration completed"
    else
        error "IDM configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: configure_ig
# Description: Executes the PingGateway configuration script (ig8.sh) with UI routes.
# -----------------------------------------------------------------------------
function configure_ig() {
    info "Configuring PingGateway (IG) with UI"
    if bash "$IG_SCRIPT"; then
        success "IG configuration completed"
    else
        error "IG configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: configure_ig_noui
# Description: Executes the PingGateway configuration script (ig8-noui.sh) without UI routes.
# -----------------------------------------------------------------------------
function configure_ig_noui() {
    info "Configuring PingGateway (IG) without UI"
    if bash "$IG_NOUI_SCRIPT"; then
        success "IG noui configuration completed"
    else
        error "IG noui configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: configure_am_via_rest
# Description: Executes the REST calls to configure AM
# -----------------------------------------------------------------------------
configure_am_via_rest(){
    info "Configuring AM via REST"
    if bash "$AM_REST_SCRIPT"; then
        success "AM REST configuration completed"
    else
        error "AM REST configuration failed"; exit 1
    fi

}

# -----------------------------------------------------------------------------
# Function: configure_ui
# Description: Executes the UI configuration script (ui8.sh) to set up Platform UI.
# -----------------------------------------------------------------------------
function configure_ui() {
    info "Configuring Platform UI"
    if bash "$UI_SCRIPT"; then
        success "Platform UI configuration completed"
    else
        error "Platform UI configuration failed"; exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: create_test_users
# Description: Creates $TEST_USER_COUNT managed users (testuser1..N) in IDM
#   via the alpha realm using a client_credentials token from the
#   'idm-provisioning' OAuth2 client (created by Step 7 — configure_am_via_rest).
#   Skipped silently when INSTALL_TEST_USERS=false or TEST_USER_COUNT<=0.
# -----------------------------------------------------------------------------
function create_test_users() {
    local count="${TEST_USER_COUNT:-0}"
    if [[ "${INSTALL_TEST_USERS:-true}" != "true" || "$count" -le 0 ]]; then
        info "Skipping test user creation (INSTALL_TEST_USERS=${INSTALL_TEST_USERS:-} TEST_USER_COUNT=${count})"
        return 0
    fi

    info "Creating ${count} test users via IDM managed/user (auth via idm-provisioning client)"
    local realm="${REALM_NAME:-alpha}"
    local am_token_url="${AM_URL}/oauth2/realms/root/realms/${realm}/access_token"
    local idm_url="http://${IDM_HOSTNAME}:${BOOT_PORT_HTTP}/openidm/managed/user?_action=create"
    local pw="${TEST_USER_PASSWORD:-!@34QWer}"
    local created=0 failed=0

    # idm-provisioning client (created by Step 7 / configure_am.sh) uses:
    #   - secret = "openidm" (hardcoded in configure_am.sh)
    #   - tokenEndpointAuthMethod = client_secret_basic
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
        warning "Response: ${token_response:0:200}"
        return 0
    fi
    info "  obtained provisioning token"

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
            info "  · testuser${i} already exists — skipping"
            created=$((created+1))
        else
            warning "  ! testuser${i} failed (HTTP $http) — ${content:0:200}"
            failed=$((failed+1))
        fi
    done

    if (( failed == 0 )); then
        success "All ${created} test users ready (password: ${pw})"
    else
        warning "${created} test users ready, ${failed} failed — investigate above"
        return 1
    fi
}

# ========================
# Main execution sequence
# ========================

info "===== 🚀 PLATFORM 8 INSTALLATION START ====="
echo
info "Select Installation Topology:"
echo "  1) Full Single-Server Install (Consolidated DS + AM + IDM + IG with 512MB limits)"
echo "  2) Multi-Server: Server 1 (Data & IDM Tier: Consolidated DS + PingIDM)"
echo "  3) Multi-Server: Server 2 (Access & Edge Tier: Tomcat AM + UI + PingGateway IG)"
read -p "Enter choice [1-3] (Default: 1): " topology_choice
topology_choice="${topology_choice:-1}"

if [[ "$topology_choice" == "2" ]]; then
    exec "${SCRIPT_DIR}/install_server1.sh"
elif [[ "$topology_choice" == "3" ]]; then
    exec "${SCRIPT_DIR}/install_server2.sh"
elif [[ "$topology_choice" != "1" ]]; then
    error "Invalid choice: $topology_choice"
    exit 1
fi

echo "Do you want to install AM with File Based Config (FBC) or DS based Config"
read -p "Enter 1 for File Based Config (FBC) [Recommended], 2 for DS based Config: " am_config_choice
am_config_choice="${am_config_choice:-1}"
if [[ "$am_config_choice" == "1" ]]; then
    am_config_type="FBC"
elif [[ "$am_config_choice" == "2" ]]; then
    am_config_type="DS"
else
    error "Invalid choice: $am_config_choice. Please choose 1 or 2."
    exit 1
fi

info "────────── 🔧 STEP 1: Stop IDM ──────────"
stop_idm_if_running && success "✅ Step 1 complete: IDM stopped"
echo

info "────────── 🧹 STEP 2: Cleanup AM ──────────"
cleanup_am && success "✅ Step 2 complete: AM cleaned up"
echo

info "────────── 📂 STEP 3: Configure DS ──────────"
configure_ds && success "✅ Step 3 complete: DS configured"

# Warning: Configuring disk thresholds for low hard disk development environments
info "Configuring disk thresholds for development environments..."
if [[ -x "${SCRIPT_DIR}/ds/configure_disk_thresholds.sh" ]]; then
    "${SCRIPT_DIR}/ds/configure_disk_thresholds.sh" || warning "Disk threshold configuration had issues but continuing..."
    success "✅ Disk thresholds configured for development environments"
else
    warning "Disk threshold script not found at ${SCRIPT_DIR}/ds/configure_disk_thresholds.sh - skipping"
fi
echo

info "────────── ⚙️ STEP 4: Deploy AM ──────────"
if [[ "$am_config_choice" == "1" ]]; then
    configure_am_fbc && success "✅ Step 4 complete: AM deployed with FBC"
else
    configure_am && success "✅ Step 4 complete: AM deployed with DS"
fi
echo

info "────────── 🔐 STEP 5: Deploy IDM ──────────"
configure_idm && success "✅ Step 5 complete: IDM deployed"
echo

info "────────── 🔐 STEP 6: Deploy IG ──────────"
configure_ig && success "✅ Step 6 complete: IG deployed"

echo

info "────────── 🔐 STEP 7: Run POSTMAN Collection ──────────"
configure_am_via_rest && success "✅ Step 7 complete: AM Configured"
echo

info "────────── 🖥️ STEP 8: Deploy UI ──────────"
configure_ui && success "✅ Step 8 complete: UI deployed"
echo

info "────────── 👥 STEP 9: Create test users ──────────"
if create_test_users; then
    success "✅ Step 9 complete: Test users ready"
else
    warning "Step 9 had failures — see above; install otherwise complete"
fi
echo

success "🎉 ALL COMPONENTS INSTALLED SUCCESSFULLY! ====="