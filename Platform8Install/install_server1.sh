#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: install_server1.sh
# Description: Installs Server 1 of 2-Server Platform 8 Topology:
#              - Consolidated Directory Services (DS) with all profiles
#              - Identity Management (IDM)
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
# STEP 1: Stop IDM if running
# -----------------------------------------------------------------------------
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
if [[ -x "./ds/configure_disk_thresholds.sh" ]]; then
    ./ds/configure_disk_thresholds.sh || warning "Disk threshold configuration completed with warnings"
    success "✅ Step 3 complete: Disk thresholds configured"
else
    warning "Disk threshold script not found - skipping"
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
info "   scp ${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem <user>@<server2-ip>:${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"
info "2. On Server 2, ensure platformconfig.env has DS_HOSTNAME set to this server's IP/hostname."
info "3. On Server 2, run: ./install_server2.sh"
echo
