#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: idm8.sh
# Description: Sets up Ping Identity IDM 8 using common environment variables.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/platformconfig.env"
elif [[ -f "${SCRIPT_DIR}/../platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/../platformconfig.env"
else
    source ./platformconfig.env
fi

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }

# ==========================
# Dynamic file detection
# ==========================
IDM_ZIP=$(find "${IDM_SOFTWARE_DIR}" -name "IDM*.zip" -type f | head -n 1)
if [[ -z "$IDM_ZIP" || ! -f "$IDM_ZIP" ]]; then
    error "No IDM*.zip file found in ${IDM_SOFTWARE_DIR}"
    exit 1
fi
info "Using IDM ZIP file: $IDM_ZIP"

# ========================================
# Function: Stop IDM if running
# ========================================
function stop_idm_if_running() {
    info "Checking for running IDM process..."
    local pid
    pid=$(pgrep -f 'openidm' || true)
    if [ -n "$pid" ]; then
        info "Found IDM running (PID $pid). Attempting graceful shutdown..."
        if [ -x "${IDM_EXTRACT_DIR}/shutdown.sh" ]; then
            "${IDM_EXTRACT_DIR}/shutdown.sh" && success "IDM stopped gracefully" || error "Graceful shutdown failed"
        else
            info "Shutdown script not found, using kill"
            kill "$pid" && success "IDM killed (PID $pid)" || error "Failed to kill IDM (PID $pid)"
        fi
    else
        info "No running IDM process found"
    fi
    sleep 10
}

# ========================================
# Function: Clean up previous installation
# ========================================
function clear_old_idm() {
    info "Cleaning up previous IDM installation..."
    rm -rf "${IDM_EXTRACT_DIR}" && success "Old IDM files removed" || error "Failed to remove old IDM files"
}

# ========================================
# Function: Extract IDM ZIP
# ========================================
function extract_idm() {
    info "Extracting IDM from ZIP..."
    if [ ! -f "${IDM_ZIP}" ]; then
        error "IDM ZIP not found: ${IDM_ZIP}"
        exit 1
    fi
    unzip -q "${IDM_ZIP}" -d "${IDM_DIR}" && success "IDM extracted to ${IDM_EXTRACT_DIR}" || { error "Extraction failed"; exit 1; }
}

# ========================================
# Function: Configure IDM
# ========================================
function configure_idm() {
    info "Configuring IDM..."

    # Remove default repo.ds.json
    if [ -f "${IDM_CONFIG_DIR}/repo.ds.json" ]; then
        info "Removing default repo.ds.json"
        rm -f "${IDM_CONFIG_DIR}/repo.ds.json" && success "Removed default repo.ds.json" || error "Failed to remove repo.ds.json"
    fi

    # Import DS cert into IDM truststore
    local cert_candidates=(
        "${IDM_CERT_FILE}"
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

    if [[ -n "$found_cert" ]]; then
        info "Importing DS certificate into IDM truststore from: $found_cert"
        # Delete existing alias if present to prevent import errors on rerun
        keytool -delete -alias ds-repo-ca-cert -keystore "${IDM_TRUSTSTORE}" -storepass:file "${IDM_STOREPASS_FILE}" 2>/dev/null || true
        keytool -importcert -noprompt \
            -alias ds-repo-ca-cert \
            -keystore "${IDM_TRUSTSTORE}" \
            -storepass:file "${IDM_STOREPASS_FILE}" \
            -file "$found_cert" && success "Certificate imported into truststore" || error "Certificate import failed"
    else
        error "Certificate file not found in any expected location (checked ${IDM_CERT_FILE})"
        exit 1
    fi

    # Update boot.properties
    info "Updating boot.properties"
    tmp_boot="${BOOT_FILE}.tmp"
    cp "${BOOT_FILE}" "$tmp_boot"
    declare -A props=(
        ["openidm.port.http"]="${BOOT_PORT_HTTP}"
        ["openidm.port.https"]="${BOOT_PORT_HTTPS}"
        ["openidm.port.mutualauth"]="${BOOT_PORT_MUTUALAUTH}"
        ["openidm.host"]="${BOOT_HOST}"
    )
    for key in "${!props[@]}"; do
        val="${props[$key]}"
        if grep -q "^${key}=" "$tmp_boot"; then
            sed -i "s|^${key}=.*|${key}=${val}|" "$tmp_boot"
        else
            echo "${key}=${val}" >> "$tmp_boot"
        fi
    done
    mv "$tmp_boot" "${BOOT_FILE}" && success "boot.properties updated" || error "Failed to update boot.properties"
}

# ========================================
# Function: Copy IDM configuration files with variable substitution
# ========================================
function copy_idm_config_files() {
    info "Copying IDM configuration files with variable substitution..."
    local src_dir="${SCRIPT_DIR}/idm"
    if [ ! -d "$src_dir" ]; then
        error "Config source directory not found: $src_dir"
        return 1
    fi
    
    # Process JSON files
    for file in "$src_dir"/*.json; do
        [ -f "$file" ] || continue
        local filename=$(basename "$file")
        local dest_file="${IDM_CONFIG_DIR}/${filename}"
        
        info "Processing JSON file: $filename with variable substitution..."
        
        # Apply variable substitution and copy to destination
        sed -e "s|{{IG_HOSTNAME}}|${IG_HOSTNAME}|g" \
            -e "s|{{IG_HTTPS_PORT}}|${IG_HTTPS_PORT}|g" \
            -e "s|{{AM_CONTEXT}}|${AM_CONTEXT}|g" \
            -e "s|{{AM_URL}}|${AM_URL}|g" \
            -e "s|{{DS_IDREPO_SERVER}}|${DS_IDREPO_SERVER}|g" \
            -e "s|{{DS_IDREPO_SERVER_LDAP_PORT}}|${DS_IDREPO_SERVER_LDAP_PORT}|g" \
            -e "s|{{DS_ADMIN_DN}}|${DS_ADMIN_DN}|g" \
            -e "s|{{LDAP_BIND_PASSWORD}}|${LDAP_BIND_PASSWORD}|g" \
            "$file" > "$dest_file"
        
        if [ $? -eq 0 ]; then
            success "Processed and copied $filename"
        else
            error "Failed to process $filename"
            return 1
        fi
    done
    
    # Process boot.properties file if it exists
    local boot_props_src="${src_dir}/resolver/boot.properties"
    if [[ -f "$boot_props_src" ]]; then
        local boot_props_dest="${IDM_EXTRACT_DIR}/resolver/boot.properties"
        info "Processing boot.properties with variable substitution..."
        
        # Create resolver directory if it doesn't exist
        mkdir -p "$(dirname "$boot_props_dest")"
        
        # Apply variable substitution to boot.properties
        sed -e "s|{{BOOT_PORT_HTTP}}|${BOOT_PORT_HTTP}|g" \
            -e "s|{{BOOT_PORT_HTTPS}}|${BOOT_PORT_HTTPS}|g" \
            -e "s|{{BOOT_PORT_MUTUALAUTH}}|${BOOT_PORT_MUTUALAUTH}|g" \
            -e "s|{{BOOT_HOST}}|${BOOT_HOST}|g" \
            "$boot_props_src" > "$boot_props_dest"
        
        if [ $? -eq 0 ]; then
            success "Processed and copied boot.properties"
        else
            error "Failed to process boot.properties"
            return 1
        fi
    fi
    
    success "All IDM config files processed and copied"
}

# ========================================
# Function: Start IDM
# ========================================
function start_idm() {
    info "Starting IDM..."
    cd "${IDM_EXTRACT_DIR}"
    export OPENIDM_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC"
    info "Running startup.sh & with OPENIDM_OPTS=${OPENIDM_OPTS}"
    ./startup.sh &
    local idm_pid=$!

    info "Waiting for IDM to start listening on port ${BOOT_PORT_HTTP}..."
    local count=0
    local max_wait=75
    local started=false
    while [[ $count -lt $max_wait ]]; do
        if (netstat -tuln 2>/dev/null || ss -tuln 2>/dev/null) | grep -q ":${BOOT_PORT_HTTP} "; then
            started=true
            success "IDM is listening on HTTP port ${BOOT_PORT_HTTP}"
            break
        fi
        sleep 3
        ((count+=3))
        if [[ $((count % 15)) -eq 0 ]]; then
            info "Waiting for IDM to initialize... (${count}/${max_wait}s)"
        fi
    done

    local logf="${IDM_LOGS_DIR}/openidm0.log"
    if [ -f "$logf" ]; then
        info "Displaying last 30 lines of IDM log:"
        tail -n 30 "$logf"
    fi

    if [[ "$started" == "true" ]]; then
        success "IDM startup completed successfully"
    else
        warning "IDM port ${BOOT_PORT_HTTP} not yet detected (may still be initializing) - continuing"
    fi
}

# ========================
# Main Execution
# ========================
stop_idm_if_running
clear_old_idm
extract_idm
configure_idm
copy_idm_config_files
start_idm