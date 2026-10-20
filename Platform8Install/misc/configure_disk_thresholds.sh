#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/platformconfig.env"
elif [[ -f "${SCRIPT_DIR}/../platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/../platformconfig.env"
else
    source ./platformconfig.env
fi

# Logging functions
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }

# Configure DS disk thresholds
function configure_disk_thresholds() {
    info "Configuring disk thresholds for all DS backends..."
    
    local ds_dir="${DS_INSTANCE_DIR:-${DS_DIR}/opendj}"
    local hostname="${DS_HOSTNAME:-${DS_IDREPO_SERVER}}"
    local port="${DS_ADMIN_CONNECTOR_PORT:-14444}"
    local backends=("cfgStore" "amCts" "amIdentityStore" "idmRepo")
    
    if [[ -x "$ds_dir/bin/dsconfig" ]]; then
        info "Configuring disk thresholds on Consolidated DS at $ds_dir..."
        for backend in "${backends[@]}"; do
            info "Setting disk thresholds for backend $backend..."
            if "$ds_dir/bin/dsconfig" \
                set-backend-prop \
                --backend-name "$backend" \
                --set disk-low-threshold:2\ gb \
                --set disk-full-threshold:1\ gb \
                --hostname "$hostname" \
                --port "$port" \
                --bindDn "$DS_ADMIN_DN" \
                --bindPassword "$DS_ADMIN_PASSWORD" \
                --trustAll \
                --no-prompt; then
                success "Disk thresholds configured for backend $backend"
            else
                warning "Failed to configure disk thresholds for backend $backend (may not exist or DS not fully ready)"
            fi
        done
    else
        # Fallback to separate instances if legacy layout is detected
        local instances=(
            "config:${DS_AMCONFIG_SERVER}:${DS_AMCONFIG_SERVER_ADMIN_CONNECTOR_PORT}:cfgStore"
            "cts:${DS_CTS_SERVER}:${DS_CTS_SERVER_ADMIN_CONNECTOR_PORT}:amCts" 
            "idrepo:${DS_IDREPO_SERVER}:${DS_IDREPO_SERVER_ADMIN_CONNECTOR_PORT}:amIdentityStore"
            "idrepo:${DS_IDREPO_SERVER}:${DS_IDREPO_SERVER_ADMIN_CONNECTOR_PORT}:idmRepo"
        )
        for instance_config in "${instances[@]}"; do
            IFS=':' read -r instance inst_host inst_port backend <<< "$instance_config"
            local legacy_dir="${DS_DIR}/${instance}/opendj"
            if [[ -x "$legacy_dir/bin/dsconfig" ]]; then
                "$legacy_dir/bin/dsconfig" \
                    set-backend-prop \
                    --backend-name "$backend" \
                    --set disk-low-threshold:2\ gb \
                    --set disk-full-threshold:1\ gb \
                    --hostname "$inst_host" \
                    --port "$inst_port" \
                    --bindDn "$DS_ADMIN_DN" \
                    --bindPassword "$DS_ADMIN_PASSWORD" \
                    --trustAll \
                    --no-prompt || warning "Failed for $backend"
            fi
        done
    fi
    
    success "Disk threshold configuration completed for all DS backends"
}

# Main execution
warning "Standalone Disk Threshold Configuration for Low disk space environments"
configure_disk_thresholds