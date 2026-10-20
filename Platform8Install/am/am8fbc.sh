#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: am8fbc.sh
# Description: Automates the deployment and configuration of Ping Advanced 
#              Identity Cloud AM 8.0.1 in File-Based Config (FBC) mode with 
#              improved, coloured logging and centralized configuration.
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
# Function: Clear previous AM deploy
# ========================================
function clear_am() {
    info "Deleting old AM files from ${TOMCAT_WEBAPPS_DIR}..."
    rm -rf "${TOMCAT_WEBAPPS_DIR}/am*" ${AMSTER_DIR} ${AM_FBC} ${AM_CFG_DIR} ${AM_DIR} && success "Old AM files removed." || error "Failed to remove old AM files"
}

# -----------------------------------------------------------------------------
# Function: deploy_amfbc_envfile
# Description: Deploy the AM FBC setenv.sh environment file to Tomcat
# -----------------------------------------------------------------------------
function deploy_amfbc_envfile(){
    info "Deploying new AM setenv.sh..."
    # Substitute template variables with actual values
    sed -e "s|{{AM_HOSTNAME}}|${AM_HOSTNAME}|g" \
        -e "s|{{AM_TRUSTSTORE}}|${AM_TRUSTSTORE}|g" \
        -e "s|{{TRUSTSTORE_PASSWORD}}|${TRUSTSTORE_PASSWORD}|g" \
        -e "s|{{DS_IDREPO_SERVER}}|${DS_IDREPO_SERVER}|g" \
        -e "s|{{DS_IDREPO_SERVER_LDAPS_PORT}}|${DS_IDREPO_SERVER_LDAPS_PORT}|g" \
        -e "s|{{DS_IDREPO_DN}}|${DS_IDREPO_DN}|g" \
        -e "s|{{DS_AMCONFIG_SERVER}}|${DS_AMCONFIG_SERVER}|g" \
        -e "s|{{DS_AMCONFIG_SERVER_LDAPS_PORT}}|${DS_AMCONFIG_SERVER_LDAPS_PORT}|g" \
        -e "s|{{DS_CTS_SERVER}}|${DS_CTS_SERVER}|g" \
        -e "s|{{DS_CTS_SERVER_LDAPS_PORT}}|${DS_CTS_SERVER_LDAPS_PORT}|g" \
        -e "s|{{DEFAULT_PASSWORD}}|${DEFAULT_PASSWORD}|g" \
        "${AM_FBC_ENV_FILE}" > "${AM_SETENV}" \
        && success "AM FBC setenv.sh file is deployed to ${AM_SETENV}" \
        || error "Failed to copy ${AM_FBC_ENV_FILE}"
    chmod +x "${AM_SETENV}" 2>/dev/null || true
    chown "${INSTALL_USER}:${INSTALL_USER}" "${AM_SETENV}" 2>/dev/null || true

    success "AM deployment delay complete."
}

# -----------------------------------------------------------------------------
# Function: initialize_fbc_directory
# Description: Initialize FBC directory structure before AM deployment
# -----------------------------------------------------------------------------
function initialize_fbc_directory() {
    info "Initializing FBC directory structure..."
    
    # Create FBC home directory
    mkdir -p "$AM_FBC"
    
    # Create required subdirectories
    local required_dirs=(
        "security"
        "security/keys"
        "security/keys/amster"
        "security/keystores"
        "config"
        "var"
        "var/audit"
        "var/debug"
        "var/stats"
    )
    
    for dir in "${required_dirs[@]}"; do
        mkdir -p "$AM_FBC/$dir"
        info "DEBUG: Created FBC directory: $AM_FBC/$dir"
    done
    
    # Set appropriate permissions
    chmod -R 700 "$AM_FBC/security"
    
    success "FBC directory structure initialized"
}

# -----------------------------------------------------------------------------
# Function: deploy_amster_keys
# Description: Deploy Amster keys with proper validation and permissions
# -----------------------------------------------------------------------------
function deploy_amster_keys() {
    info "Deploying Amster keys for FBC..."
    
    local keys_source="${SCRIPT_DIR}/misc/keys"
    local keys_dest="$AM_FBC/security"
    
    # Validate source keys exist
    if [[ ! -d "$keys_source" ]]; then
        error "Keys source directory not found: $keys_source"
        return 1
    fi
    
    # Check for required key files
    local required_keys=(
        "amster/amster_rsa"
        "amster/amster_rsa.pub"
    )
    
    for key in "${required_keys[@]}"; do
        if [[ ! -f "$keys_source/$key" ]]; then
            error "Required key not found: $keys_source/$key"
            return 1
        fi
    done
    
    # Copy keys directory
    if ! cp -r "$keys_source" "$keys_dest/"; then
        error "Failed to copy keys directory"
        return 1
    fi
    
    # Set proper permissions for security
    chmod -R 600 "$keys_dest/keys/amster/"*
    chmod 700 "$keys_dest/keys/amster"
    
    # Verify keys are accessible
    if [[ ! -r "$AM_FBC/security/keys/amster/amster_rsa" ]]; then
        error "Amster private key not readable after deployment"
        return 1
    fi
    
    success "Amster keys deployed and secured"
}

# -----------------------------------------------------------------------------
# Function: deploy_amfbc
# Description: Deploy the new AM WAR and display deployment status
# -----------------------------------------------------------------------------

function deploy_amfbc() {
    info "Deploying AM WAR for FBC..."
    
    INSTALLATION_STATE="AM_DEPLOYMENT"
    
    # Copy WAR file
    if ! cp "$AM_WAR" "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war"; then
        error "Failed to copy AM WAR"
        return 1
    fi
    
    success "AM WAR copied to webapps"
    
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
    
    # Monitor deployment
    info "Monitoring AM deployment..."
    local max_wait=120
    local count=0
    
    while [[ $count -lt $max_wait ]]; do
        # Check if WAR is unpacked
        if [[ -d "${TOMCAT_WEBAPPS_DIR}/am/WEB-INF" ]]; then
            # Check if FBC initialization has started
            if [[ -f "$AM_FBC/.version" ]] || [[ -f "$AM_FBC/config/boot.json" ]]; then
                success "AM deployed with FBC initialization"
                FBC_CONFIGURED=true
                return 0
            fi
            
            # Check Tomcat logs for FBC initialization
            if [[ -f "$TOMCAT_DIR/logs/catalina.out" ]]; then
                if tail -100 "$TOMCAT_DIR/logs/catalina.out" | grep -q "File based configuration found"; then
                    info "FBC initialization detected"
                fi
            fi
        fi
        
        sleep 5
        ((count+=5))
        
        if [[ $((count % 20)) -eq 0 ]]; then
            info "Waiting for deployment... ($count/$max_wait seconds)"
        fi
    done
    
    if [[ ! -d "${TOMCAT_WEBAPPS_DIR}/am/WEB-INF" ]]; then
        error "AM WAR failed to deploy"
        return 1
    fi
    
    warning "AM deployed but FBC may not be fully initialized"
    
    INSTALLATION_STATE="FBC_DEPLOYED"
}
# ==================================================================================
# Function: setup_amster
# Purpose:  Setup Amster with validation and FBC readiness checks
# ==================================================================================
function setup_amster() {
    info "Setting up Amster..."
    
    info "DEBUG: Amster setup environment check:"
    info "DEBUG: AMSTER_ZIP=$AMSTER_ZIP"
    info "DEBUG: AMSTER_SOFTWARE_DIR=$AMSTER_SOFTWARE_DIR"
    info "DEBUG: AMSTER_DIR=$AMSTER_DIR"
    info "DEBUG: AM_FBC=$AM_FBC"
    
    # Ensure JAVA_HOME is set for Amster
    info "DEBUG: Ensuring JAVA_HOME is set..."
    ensure_java_home || return 1
    info "DEBUG: JAVA_HOME verified: $JAVA_HOME"
    
    # Check if AMSTER_ZIP exists
    if [[ -f "$AMSTER_ZIP" ]]; then
        success "DEBUG: Amster ZIP file found at $AMSTER_ZIP"
        info "DEBUG: Amster ZIP file size: $(ls -lh "$AMSTER_ZIP" | awk '{print $5}')"
    else
        error "DEBUG: Amster ZIP file not found at $AMSTER_ZIP"
        return 1
    fi
    
    # Remove old Amster directory
    info "DEBUG: Removing old Amster directory..."
    rm -rf "${AMSTER_DIR}"
    
    # Wait for FBC to be ready
    local FBC_CONFIGURED=false
    if [[ ! "$FBC_CONFIGURED" == "true" ]]; then
        info "Waiting for FBC initialization to complete..."
        info "DEBUG: Checking for FBC boot.json file at: $AM_FBC/config/boot.json"
        
        local wait_count=0
        while [[ $wait_count -lt 60 ]]; do
            if [[ -f "$AM_FBC/config/boot.json" ]]; then
                FBC_CONFIGURED=true
                success "DEBUG: FBC boot.json found"
                break
            fi
            info "DEBUG: FBC boot.json not found, waiting... (${wait_count}s elapsed)"
            sleep 2
            ((wait_count+=2))
        done
        
        if [[ ! "$FBC_CONFIGURED" == "true" ]]; then
            warning "FBC may not be fully initialized"
            info "DEBUG: Final FBC directory check:"
            ls -la "$AM_FBC/" 2>/dev/null || warning "DEBUG: Cannot list AM_FBC directory"
            ls -la "$AM_FBC/config/" 2>/dev/null || warning "DEBUG: Cannot list AM_FBC/config directory"
        fi
    fi
    
    # Unpack Amster
    info "DEBUG: Unpacking Amster from $AMSTER_ZIP to $AMSTER_SOFTWARE_DIR"
    if ! unzip -q -o "$AMSTER_ZIP" -d "$AMSTER_SOFTWARE_DIR"; then
        error "Failed to unzip Amster"
        error "DEBUG: Unzip command failed, checking directory permissions:"
        ls -la "$AMSTER_SOFTWARE_DIR" || error "DEBUG: Cannot access AMSTER_SOFTWARE_DIR"
        return 1
    fi
    success "DEBUG: Amster unpacked successfully"
    
    # Verify Amster executable
    info "DEBUG: Checking Amster executable at ${AMSTER_DIR}/amster"
    if [[ ! -x "${AMSTER_DIR}/amster" ]]; then
        error "Amster executable not found or not executable"
        error "DEBUG: Amster directory contents:"
        ls -la "${AMSTER_DIR}/" || error "DEBUG: Cannot list AMSTER_DIR"
        return 1
    fi
    success "DEBUG: Amster executable found and is executable"
    
    # Test Amster with basic functionality
    info "DEBUG: Testing Amster basic functionality..."
    if ! "${AMSTER_DIR}/amster" --version >/dev/null 2>&1; then
        error "Amster failed basic functionality test"
        error "DEBUG: Running amster --version with full output:"
        "${AMSTER_DIR}/amster" --version || true
        return 1
    fi
    success "DEBUG: Amster basic functionality test passed"
    
    success "Amster setup completed"
}

# -----------------------------------------------------------------------------
# Enhanced Amster command wrapper with error filtering
# -----------------------------------------------------------------------------
function run_amster_fbc_command() {
    local command=$1
    local description=$2
    
    info "Executing: $description"
    
    # Ensure JAVA_HOME is set for Amster
    ensure_java_home || return 1

    # Pass truststore to Amster JVM
    export JAVA_OPTS="${JAVA_OPTS:-} -Djavax.net.ssl.trustStore=${AM_TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}"
    export AMSTER_OPTS="${AMSTER_OPTS:-} -Djavax.net.ssl.trustStore=${AM_TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}"

    # Create temporary log file
    local amster_log="/tmp/amster-fbc-output-$$.log"
    
    # Clear previous log
    > "$amster_log"
    
    # Run Amster command
    if echo "$command" | "${AMSTER_DIR}/amster" > "$amster_log" 2>&1; then
        # Check for errors in output, but ignore common harmless warnings
        if grep -qi "error\|failed\|exception" "$amster_log"; then
            # Filter out harmless warnings
            local filtered_errors=$(grep -i "error\|failed\|exception" "$amster_log" | \
                                   grep -v "ansi will be disabled" | \
                                   grep -v "Could not load library" | \
                                   grep -v "jansi" | \
                                   grep -v "libjansi")
            
            if [[ -n "$filtered_errors" ]]; then
                # Some errors are expected (like realm already exists)
                if echo "$filtered_errors" | grep -qi "already exists"; then
                    warning "$description - resource already exists"
                    rm -f "$amster_log"
                    return 0
                else
                    error "$description reported errors:"
                    echo "$filtered_errors" | head -10
                    rm -f "$amster_log"
                    return 1
                fi
            fi
        fi
        
        success "$description completed successfully"
        rm -f "$amster_log"
        return 0
    else
        error "$description failed"
        info "DEBUG: Full amster output:"
        cat "$amster_log"
        rm -f "$amster_log"
        return 1
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

# -----------------------------------------------------------------------------
# Tomcat management functions
# -----------------------------------------------------------------------------
function stop_tomcat() {
    info "Stopping Tomcat..."
    
    # Try systemctl first
    if systemctl is-enabled tomcat >/dev/null 2>&1; then
        if sudo systemctl stop tomcat; then
            success "Tomcat stopped via systemctl"
        else
            warning "systemctl stop failed"
        fi
    fi
    
    # Try shutdown script
    if [[ -x "$TOMCAT_BIN_DIR/shutdown.sh" ]]; then
        "$TOMCAT_BIN_DIR/shutdown.sh" 2>/dev/null || true
    fi
    
    # Wait for shutdown
    local count=0
    while [[ $count -lt 30 ]] && pgrep -f "catalina.*start" >/dev/null 2>&1; do
        sleep 1
        ((count++))
    done
    
    # Force kill if still running
    if pgrep -f "catalina.*start" >/dev/null 2>&1; then
        warning "Force killing Tomcat processes..."
        pkill -9 -f "catalina.*start" 2>/dev/null || true
        sleep 2
    fi
    
    success "Tomcat stopped"
}

function start_tomcat() {
    info "Starting Tomcat..."
    
    # Ensure it's not already running
    if pgrep -f "catalina.*start" >/dev/null 2>&1; then
        warning "Tomcat is already running"
        return 0
    fi
    
    # Start Tomcat
    if systemctl is-enabled tomcat >/dev/null 2>&1; then
        if sudo systemctl start tomcat; then
            success "Tomcat started via systemctl"
        else
            error "systemctl start failed"
            return 1
        fi
    else
        if [[ -x "$TOMCAT_BIN_DIR/startup.sh" ]]; then
            "$TOMCAT_BIN_DIR/startup.sh"
        else
            error "No Tomcat startup method available"
            return 1
        fi
    fi
    
    # Wait for Tomcat to be ready
    info "Waiting for Tomcat to be ready..."
    local count=0
    while [[ $count -lt 60 ]]; do
        if (netstat -tuln 2>/dev/null || ss -tuln 2>/dev/null) | grep -q ":${TOMCAT_HTTP_PORT} "; then
            if curl -s -o /dev/null "http://localhost:${TOMCAT_HTTP_PORT}" 2>/dev/null; then
                success "Tomcat is ready"
                return 0
            fi
        fi
        sleep 2
        ((count+=2))
    done
    
    error "Tomcat failed to start properly"
    return 1
}

# -----------------------------------------------------------------------------
# Wait for AM with FBC to be ready
# -----------------------------------------------------------------------------
function wait_for_am_ready() {
    info "Waiting for AM with FBC to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Check basic connectivity
        local status=$(curl -s -o /dev/null -w "%{http_code}" "$AM_URL/json/serverinfo/*" 2>/dev/null || echo "000")
        
        if [[ "$status" == "200" ]]; then
            # Check for basic FBC initialization - more lenient approach
            if [[ -d "$AM_FBC/config" ]] && [[ -f "$AM_FBC/config/boot.json" ]]; then
                success "AM with FBC is ready for Amster operations"
                return 0
            elif [[ -d "$AM_FBC/config/services" ]]; then
                # If services directory exists, FBC is probably ready enough
                success "AM with FBC services initialized - proceeding"
                return 0
            else
                info "AM responding but FBC initialization ongoing..."
            fi
        elif [[ "$status" == "302" ]]; then
            info "AM redirecting (configuration needed)..."
        else
            info "AM not responding yet (HTTP $status)..."
        fi
        
        ((attempt++))
        sleep 5
        
        if [[ $((attempt % 12)) -eq 0 ]]; then
            info "Still waiting... (attempt $attempt/$max_attempts)"
            
            # After 2 minutes, be more lenient
            if [[ $attempt -gt 24 ]]; then
                info "Extended wait - checking if AM is at least responding..."
                if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
                    warning "AM responding but FBC not fully initialized - proceeding anyway"
                    return 0
                fi
            fi
        fi
    done
    
    error "AM failed to initialize after $((max_attempts * 5)) seconds"
    return 1
}

# ========================================
# Function: Create Alpha Realm
# ========================================
function create_alpha_realm() {
    info "Creating Alpha realm..."
    
    # Pre-flight debug checks (keeping some key validation)
    info "DEBUG: Pre-amster environment check:"
    info "DEBUG: JAVA_HOME=$JAVA_HOME"
    info "DEBUG: AM_URL=$AM_URL"
    info "DEBUG: AM_FBC=$AM_FBC"
    info "DEBUG: AMSTER_DIR=$AMSTER_DIR"
    
    local key_file="${AM_FBC}/security/keys/amster/amster_rsa"
    if [[ -f "$key_file" ]]; then
        success "DEBUG: Amster key file found at $key_file"
        info "DEBUG: Key file permissions: $(stat -c '%a' "$key_file" 2>/dev/null || stat -f '%A' "$key_file")"
    else
        error "DEBUG: Amster key file not found at $key_file"
        return 1
    fi
    
    # Use enhanced wrapper for amster commands
    local amster_script="connect -k ${AM_FBC}/security/keys/amster/amster_rsa ${AM_URL}
create Realms --global --body '{\"_id\": \"L2FscGhh\", \"parentPath\": \"/\", \"active\": true, \"name\": \"alpha\", \"aliases\": []}'
:exit"

    run_amster_fbc_command "$amster_script" "Alpha realm creation"
}

# ========================================
# Function: Import sample journeys
# ========================================
function import_journeys() {
    info "Importing authentication journeys..."
    
    info "DEBUG: Journey import pre-checks:"
    info "DEBUG: AM_JOURNEYS_DIR=$AM_JOURNEYS_DIR"
    
    # Check if journey directory exists
    if [[ ! -d "$AM_JOURNEYS_DIR" ]]; then
        warning "Journey directory not found: $AM_JOURNEYS_DIR"
        return 0
    fi
    
    success "DEBUG: Journeys directory found at $AM_JOURNEYS_DIR"
    info "DEBUG: Journeys directory contents:"
    ls -la "$AM_JOURNEYS_DIR" | head -10 || warning "DEBUG: Cannot list journeys directory"
    
    # Use enhanced wrapper for amster commands
    local amster_script="connect -k ${AM_FBC}/security/keys/amster/amster_rsa ${AM_URL}
import-config --path ${AM_JOURNEYS_DIR}
:exit"

    run_amster_fbc_command "$amster_script" "Journey import"
}

# ==========================
# Main execution sequence
# ==========================
ensure_java_home
stop_tomcat
clear_am
deploy_amfbc_envfile
initialize_fbc_directory
deploy_amster_keys
start_tomcat
deploy_amfbc
restart_am
wait_for_am_ready
setup_amster
create_alpha_realm
import_journeys
restart_am