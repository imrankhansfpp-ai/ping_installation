#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: install_server1.sh
# Description: Installs Server 1 of 2-Server Platform 8 Topology:
#              - Consolidated Directory Services (DS) with all profiles
#              - Identity Management (IDM)
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
info " 🚀 PLATFORM 8 - SERVER 1 INSTALLATION (DATA & IDENTITY TIER)"
info " Components: Consolidated DS (all profiles) + PingIDM"
info " JVM Heap Target: 512MB per component (Optimal for 8GB RAM host)"
info "================================================================="
echo

# -----------------------------------------------------------------------------
# Function: stop_idm_if_running
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
# Function: preflight_checks
# -----------------------------------------------------------------------------
function preflight_checks() {
    info "Running pre-flight checks for Server 1..."
    local missing=0

    local ds_zip
    ds_zip=$(find "${DS_SOFTWARE_DIR}" -name "DS*.zip" -type f 2>/dev/null | head -n 1) || true
    if [[ -z "$ds_zip" ]]; then
        error "Missing Directory Services binary! Please place DS*.zip in: ${DS_SOFTWARE_DIR}/"
        missing=1
    else
        success "Found DS package: $(basename "$ds_zip")"
    fi

    local idm_zip
    idm_zip=$(find "${IDM_SOFTWARE_DIR}" -name "IDM*.zip" -type f 2>/dev/null | head -n 1) || true
    if [[ -z "$idm_zip" ]]; then
        error "Missing Identity Management binary! Please place IDM*.zip in: ${IDM_SOFTWARE_DIR}/"
        missing=1
    else
        success "Found IDM package: $(basename "$idm_zip")"
    fi

    if [[ $missing -ne 0 ]]; then
        error "Pre-flight checks failed. Please add the required software packages and rerun."
        exit 1
    fi
    success "Pre-flight checks passed"
    echo
}

# -----------------------------------------------------------------------------
# STEP 1: Stop IDM if running
# -----------------------------------------------------------------------------
preflight_checks

info "────────── 🔧 STEP 1: Stop IDM if running ──────────"
stop_idm_if_running && success "✅ Step 1 complete: IDM stopped"
echo

# -----------------------------------------------------------------------------
# STEP 2: Configure Consolidated Directory Server
# -----------------------------------------------------------------------------
info "────────── 📂 STEP 2: Configure Consolidated DS (512MB) ──────────"
if bash "$DS_SCRIPT"; then
    success "✅ Step 2 complete: Consolidated DS installed with all profiles"
else
    error "DS configuration failed"
    exit 1
fi
echo

# -----------------------------------------------------------------------------
# STEP 3: Configure Disk Thresholds
# -----------------------------------------------------------------------------
info "────────── 💽 STEP 3: Configure Disk Thresholds for Dev ──────────"
if [[ -x "${SCRIPT_DIR}/ds/configure_disk_thresholds.sh" ]]; then
    "${SCRIPT_DIR}/ds/configure_disk_thresholds.sh" || warning "Disk threshold configuration completed with warnings"
    success "✅ Step 3 complete: Disk thresholds configured"
else
    warning "Disk threshold script not found at ${SCRIPT_DIR}/ds/configure_disk_thresholds.sh - skipping"
fi
echo

# -----------------------------------------------------------------------------
# STEP 4: Deploy IDM
# -----------------------------------------------------------------------------
info "────────── 🔐 STEP 4: Deploy IDM (512MB) ──────────"
if bash "$IDM_SCRIPT"; then
    success "✅ Step 4 complete: IDM deployed"
else
    error "IDM configuration failed"
    exit 1
fi
echo

# -----------------------------------------------------------------------------
# Summary & Next Steps for Server 2
# -----------------------------------------------------------------------------
info "================================================================="
success "🎉 SERVER 1 INSTALLATION COMPLETED SUCCESSFULLY!"
info "================================================================="
echo
info "📌 NEXT STEPS TO COMPLETE PLATFORM 8 SETUP ON SERVER 2:"
info "1. Copy the DS CA Certificate from this server to Server 2:"
info "   Command option A (Recommended - copies directly into Server 2's repo):"
info "     scp ./misc/keys/ds-ca-cert.pem <user>@<server2-ip>:/path/to/Platform8Install/misc/keys/"
info "   Command option B (into AM keystores directory):"
info "     scp ${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem <user>@<server2-ip>:${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
echo
info "2. On Server 2, verify platformconfig.env has:"
info "     SERVER1_IP set to this server's IP address"
info "     SERVER2_IP set to Server 2's IP address"
info "     DS_HOSTNAME and IDM_HOSTNAME resolving to Server 1"
echo
info "3. On Server 2, run prerequisites setup then launch installer:"
info "     ./misc/platform8-setup.sh"
info "     ./install_server2.sh"
echo
