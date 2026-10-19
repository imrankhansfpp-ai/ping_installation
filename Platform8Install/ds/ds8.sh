#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: ds8.sh
# Description: Sets up Ping Directory Server (DS) instances for AM config, CTS, 
#              and IDRepo with improved, coloured logging and centralized 
#              configuration.
################################################################################

# ==========================
# Load environment variables
# ==========================
source ./platformconfig.env

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }

# ==========================
# Dynamic file detection
# ==========================
DS_ZIP_FILE=$(find "${DS_SOFTWARE_DIR}" -name "DS*.zip" -type f | head -n 1)
if [[ -z "$DS_ZIP_FILE" || ! -f "$DS_ZIP_FILE" ]]; then
    error "No DS*.zip file found in ${DS_SOFTWARE_DIR}"
    exit 1
fi
info "Using DS file: $DS_ZIP_FILE"

# ========================================
# Function: Kill all DS processes
# ========================================
function kill_ds_processes() {
    info "Searching for running DS processes..."
    local ds_pids
    ds_pids=$(ps -ef | grep 'org.opends.server.core.DirectoryServer' | grep -v grep | awk '{print $2}') || ds_pids=""
    if [ -z "$ds_pids" ]; then
        info "No running DS processes found."
    else
        info "Killing DS processes: $ds_pids"
        if kill -9 $ds_pids; then
            success "DS processes terminated."
        else
            error "Failed to kill some DS processes"
        fi
    fi
}

# ========================================
# Function: Create AM truststore
# ========================================
function prepare_am_truststore() {
    info "Creating AM truststore..."
    sudo rm -rf "${AM_TRUSTSTORE_FOLDER}"
    mkdir -p "${AM_TRUSTSTORE_FOLDER}"
    sudo cp "${jvm_cacerts:-$(dirname $(dirname $(readlink $(readlink $(which javac)))))/lib/security/cacerts}" "${AM_TRUSTSTORE}"
    sudo chown "${INSTALL_USER}:${INSTALL_USER}" "${AM_TRUSTSTORE}"
    sudo chmod 644 "${AM_TRUSTSTORE}"
    success "AM truststore created at ${AM_TRUSTSTORE}"
}

# ========================================
# Function: Import DS certs into AM truststore
# ========================================
function prepare_ds_certs() {
    info "Importing DS certificates into AM truststore..."
    for cert in ds-ca-cert ds-repo-ca-cert ds-config-ca-cert ds-cts-ca-cert; do
        if [[ -f "${AM_TRUSTSTORE_FOLDER}/${cert}.pem" ]]; then
            keytool -importcert -file "${AM_TRUSTSTORE_FOLDER}/${cert}.pem" \
                -keystore "${AM_TRUSTSTORE}" -storepass "${TRUSTSTORE_PASSWORD}" \
                -alias "${cert}" -noprompt && info "Imported ${cert}" || warning "Failed to import ${cert}"
        fi
    done
    success "DS certificates imported"
}

# ========================================
# Function: Install Consolidated Single DS Store
# Profiles: am-identity-store, idm-repo, am-cts, am-config
# Memory: Enforces 512MB JVM Heap
# ========================================
function install_single_ds() {
    info "Installing Single Consolidated Directory Server (all profiles) at ${DS_INSTANCE_DIR}..."
    rm -rf "${DS_DIR}" && mkdir -p "${DS_DIR}"
    unzip -q "${DS_ZIP_FILE}" -d "${DS_DIR}"
    cd "${DS_INSTANCE_DIR}"

    # Enforce 512MB heap limit for DS installation and execution
    export OPENDJ_JAVA_ARGS="-Xms256m -Xmx512m -XX:MaxRAMPercentage=20"
    info "Configuring DS setup with JVM memory limit: ${OPENDJ_JAVA_ARGS}"

    ./setup \
        --rootUserDN "${DS_ADMIN_DN}" \
        --rootUserPassword "${DS_ADMIN_PASSWORD}" \
        --monitorUserPassword "${DS_ADMIN_PASSWORD}" \
        --hostname "${DS_HOSTNAME}" \
        --ldapPort "${DS_LDAP_PORT}" \
        --ldapsPort "${DS_LDAPS_PORT}" \
        --httpPort "${DS_HTTP_PORT}" \
        --httpsPort "${DS_HTTPS_PORT}" \
        --adminConnectorPort "${DS_ADMIN_CONNECTOR_PORT}" \
        --enableStartTLS \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --profile am-identity-store:8.0.0 \
        --set am-identity-store/amIdentityStoreAdminPassword:"${DEFAULT_PASSWORD}" \
        --profile idm-repo \
        --set idm-repo/domain:"${DS_REPO_SUFFIX}" \
        --profile am-cts \
        --set am-cts/amCtsAdminPassword:"${DEFAULT_PASSWORD}" \
        --set am-cts/tokenExpirationPolicy:am-sessions-only \
        --profile am-config \
        --set am-config/amConfigAdminPassword:"${DEFAULT_PASSWORD}" \
        --start \
        --quiet \
        --acceptLicense

    # Persist 512MB JVM heap in config/java.properties
    if [[ -f "./config/java.properties" ]]; then
        info "Configuring DS startup heap to 512MB in java.properties..."
        sed -i 's/^start-ds.java-args=.*/start-ds.java-args=-Xms256m -Xmx512m/' ./config/java.properties || true
    fi

    # Export CA Certificate
    info "Exporting DS CA Certificate..."
    ./bin/dskeymgr export-ca-cert \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --outputFile "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem"

    # Backward compatibility aliases
    cp -f "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem" "${AM_TRUSTSTORE_FOLDER}/ds-repo-ca-cert.pem" 2>/dev/null || true
    cp -f "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem" "${AM_TRUSTSTORE_FOLDER}/ds-config-ca-cert.pem" 2>/dev/null || true
    cp -f "${AM_TRUSTSTORE_FOLDER}/ds-ca-cert.pem" "${AM_TRUSTSTORE_FOLDER}/ds-cts-ca-cert.pem" 2>/dev/null || true

    success "Single Consolidated Directory Server installed at ${DS_INSTANCE_DIR}"
}

# ========================================
# Function: Test secure LDAP connectivity
# ========================================
function test_ldap_secure_bind() {
    info "Testing secure LDAP connections against Single Consolidated DS..."
    local PASSWORD="${DS_ADMIN_PASSWORD}"
    local host="${DS_HOSTNAME}"
    local port="${DS_LDAPS_PORT}"

    for label in Config IDRepo CTS; do
        case $label in
            Config)
                bindDN="uid=am-config,ou=admins,ou=am-config"
                base="ou=am-config";;
            IDRepo)
                bindDN="uid=am-identity-bind-account,ou=admins,${DS_IDREPO_DN}"
                base="ou=identities";;
            CTS)
                bindDN="uid=openam_cts,ou=admins,ou=famrecords,ou=openam-session,ou=tokens"
                base="ou=famrecords,ou=openam-session,ou=tokens";;
        esac
        info "→ Testing ${label} backend bind"
        if "${DS_INSTANCE_DIR}/bin/ldapsearch" -h "$host" -p "$port" -D "$bindDN" -w "$PASSWORD" -b "$base" -Z --trustStorePath "$AM_TRUSTSTORE" "objectclass=*" dn >/dev/null 2>&1; then
            success "${label} LDAP bind succeeded with:"
            success "${DS_INSTANCE_DIR}/bin/ldapsearch -h $host -p $port -D $bindDN -w xxxx -b $base -Z --trustStorePath $AM_TRUSTSTORE objectclass=* dn"
        else
            warning "${label} LDAP bind test returned non-zero (verify certificate trust and service status)"
        fi
    done
}

# ==========================
# Main execution sequence
# ==========================
kill_ds_processes
prepare_am_truststore
install_single_ds
prepare_ds_certs
test_ldap_secure_bind