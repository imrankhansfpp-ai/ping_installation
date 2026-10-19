#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: platform8-control.sh
# Description: Service management script for Platform 8
#              Handles start, stop, restart, status, and backup operations
################################################################################

# Load configuration
source ./platformconfig.env

# -----------------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------------
function info()    { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;32m[✔]\033[0m     $*"; }
function warning() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;33m[⚠]\033[0m     $*"; }
function error()   { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;31m[✖]\033[0m     $*"; }

# -----------------------------------------------------------------------------
# Service Management Functions
# -----------------------------------------------------------------------------
function start_all_services() {
    info "Starting Platform 8 services..."
    
    # Start DS instances first (dependency order)
    info "Starting Directory Services..."
    local consolidated_ds="${DS_INSTANCE_DIR:-${DS_DIR}/opendj}"
    if [[ -d "$consolidated_ds" && -x "$consolidated_ds/bin/start-ds" ]]; then
        info "Starting Consolidated DS..."
        cd "$consolidated_ds"
        ./bin/start-ds --quiet || warning "Failed to start Consolidated DS"
        cd - >/dev/null
    else
        for instance in config cts idrepo; do
            local ds_dir="${DS_DIR}/${instance}/opendj"
            if [[ -d "$ds_dir" && -x "$ds_dir/bin/start-ds" ]]; then
                info "Starting DS $instance..."
                cd "$ds_dir"
                ./bin/start-ds --quiet || warning "Failed to start DS $instance"
                cd - >/dev/null
            fi
        done
    fi
    
    # Start Tomcat (AM) - depends on DS
    info "Starting Tomcat (AM)..."
    if systemctl is-enabled tomcat >/dev/null 2>&1; then
        sudo systemctl start tomcat || warning "Failed to start Tomcat via systemctl"
    else
        if [[ -x "$TOMCAT_DIR/bin/startup.sh" ]]; then
            sudo "$TOMCAT_DIR/bin/startup.sh" || warning "Failed to start Tomcat directly"
        else
            warning "Tomcat startup script not found"
        fi
    fi
    
    # Start IDM - depends on DS and AM
    info "Starting IDM..."
    if [[ -d "$IDM_EXTRACT_DIR" && -x "$IDM_EXTRACT_DIR/startup.sh" ]]; then
        cd "$IDM_EXTRACT_DIR"
        nohup ./startup.sh > /dev/null 2>&1 &
        cd - >/dev/null
        info "IDM startup initiated"
    else
        warning "IDM not found or startup script not executable at $IDM_EXTRACT_DIR"
    fi
    
    # Start IG - depends on AM and IDM
    info "Starting IG..."
    if [[ -d "$IG_DIR" && -x "$IG_DIR/bin/start.sh" ]]; then
        cd "$IG_DIR"
        nohup ./bin/start.sh > /dev/null 2>&1 &
        cd - >/dev/null
    else
        warning "IG not found or start script missing"
    fi
    
    info "Waiting for services to start..."
    sleep 10
    
    success "Service startup completed"
    show_service_status
}

function stop_all_services() {
    info "Stopping Platform 8 services..."
    
    # Stop in reverse dependency order
    
    # Stop IG
    info "Stopping IG..."
    pkill -f "openig|identity-gateway|\.openig" 2>/dev/null || true
    
    # Stop IDM
    info "Stopping IDM..."
    if [[ -d "$IDM_EXTRACT_DIR" && -x "$IDM_EXTRACT_DIR/shutdown.sh" ]]; then
        cd "$IDM_EXTRACT_DIR"
        ./shutdown.sh > /dev/null 2>&1 || true
        cd - >/dev/null
        info "IDM shutdown initiated"
    fi
    pkill -f "openidm" 2>/dev/null || true
    
    # Stop Tomcat (AM)
    info "Stopping Tomcat (AM)..."
    if systemctl is-enabled tomcat >/dev/null 2>&1; then
        sudo systemctl stop tomcat || true
    else
        if [[ -x "$TOMCAT_DIR/bin/shutdown.sh" ]]; then
            sudo "$TOMCAT_DIR/bin/shutdown.sh" || true
        fi
    fi
    # Forceful stop if still running
    pkill -f "catalina.*start" 2>/dev/null || true
    
    # Stop DS instances last
    info "Stopping Directory Services..."
    local consolidated_ds="${DS_INSTANCE_DIR:-${DS_DIR}/opendj}"
    if [[ -d "$consolidated_ds" && -x "$consolidated_ds/bin/stop-ds" ]]; then
        info "Stopping Consolidated DS..."
        cd "$consolidated_ds"
        ./bin/stop-ds --quiet 2>/dev/null || true
        cd - >/dev/null
    fi
    for instance in config cts idrepo; do
        local ds_dir="${DS_DIR}/${instance}/opendj"
        if [[ -d "$ds_dir" && -x "$ds_dir/bin/stop-ds" ]]; then
            info "Stopping DS $instance..."
            cd "$ds_dir"
            ./bin/stop-ds --quiet 2>/dev/null || true
            cd - >/dev/null
        fi
    done
    
    success "All services stopped"
}

function restart_all_services() {
    info "Restarting Platform 8 services..."
    stop_all_services
    info "Waiting for services to fully stop..."
    sleep 5
    start_all_services
}

function show_service_status() {
    info "Platform 8 Service Status:"
    echo "========================="
    
    # DS Status
    local consolidated_ds="${DS_INSTANCE_DIR:-${DS_DIR}/opendj}"
    if [[ -d "$consolidated_ds" ]]; then
        local port="${DS_LDAPS_PORT:-1636}"
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            success "Consolidated DS: Running on LDAPS port $port"
        else
            error "Consolidated DS: Not running (port $port)"
        fi
    else
        for instance in config cts idrepo; do
            local port_var="DS_$(echo $instance | tr '[:lower:]' '[:upper:]')_SERVER_LDAPS_PORT"
            if [[ "$instance" == "config" ]]; then
                port_var="DS_AMCONFIG_SERVER_LDAPS_PORT"
            fi
            local port="${!port_var:-}"
            if [[ -n "$port" ]] && netstat -tuln 2>/dev/null | grep -q ":$port "; then
                success "DS $instance: Running on port $port"
            else
                error "DS $instance: Not running (port $port)"
            fi
        done
    fi
    
    # Tomcat Status
    if systemctl is-active tomcat >/dev/null 2>&1; then
        success "Tomcat (AM): Running (systemctl)"
    elif pgrep -f "catalina.*start" >/dev/null; then
        success "Tomcat (AM): Running (process)"
    else
        error "Tomcat (AM): Not running"
    fi
    
    # IDM Status
    if pgrep -f "openidm" >/dev/null; then
        success "IDM: Running"
    else
        error "IDM: Not running"
    fi
    
    # IG Status
    if pgrep -f "openig|identity-gateway|\.openig" >/dev/null 2>&1; then
        success "IG: Running"
    else
        error "IG: Not running"
    fi
    
    echo "========================="
}

function create_backup() {
    local backup_dir="/opt/platform8/backups/backup-$(date +%Y%m%d-%H%M%S)"
    info "Creating backup in $backup_dir..."
    
    sudo mkdir -p "$backup_dir"
    
    # Backup DS data
    for instance in config cts idrepo; do
        if [[ -d "${DS_DIR}/${instance}" ]]; then
            info "Backing up DS $instance..."
            sudo cp -r "${DS_DIR}/${instance}" "$backup_dir/ds-${instance}" 2>/dev/null || true
        fi
    done
    
    # Backup AM configuration
    if [[ -d "$AM_CONFIG_DIR" ]]; then
        info "Backing up AM configuration..."
        sudo cp -r "$AM_CONFIG_DIR" "$backup_dir/am-config" 2>/dev/null || true
    fi
    
    # Backup IDM configuration
    if [[ -d "$IDM_CONFIG_DIR" ]]; then
        info "Backing up IDM configuration..."
        sudo cp -r "$IDM_CONFIG_DIR" "$backup_dir/idm-config" 2>/dev/null || true
    fi
    
    # Backup IG configuration
    if [[ -d "$IG_DIR/config" ]]; then
        info "Backing up IG configuration..."
        sudo cp -r "$IG_DIR/config" "$backup_dir/ig-config" 2>/dev/null || true
    fi
    
    success "Backup created at $backup_dir"
}

function install_tomcat() {
    info "Installing Tomcat 10 using platform8-setup.sh..."
    
    local setup_script="./bin/platform8-setup.sh"
    
    if [[ ! -f "$setup_script" ]]; then
        error "Setup script not found: $setup_script"
    fi
    
    if [[ ! -x "$setup_script" ]]; then
        chmod +x "$setup_script"
    fi
    
    # Run tomcat installation only
    "$setup_script" tomcat
}

function show_usage() {
    echo "Platform 8 Service Control Script"
    echo "Usage: $0 {start|stop|restart|status|backup|install-tomcat|help}"
    echo ""
    echo "Commands:"
    echo "  start         - Start all Platform 8 services"
    echo "  stop          - Stop all Platform 8 services"
    echo "  restart       - Restart all Platform 8 services"
    echo "  status        - Show status of all services"
    echo "  backup        - Create configuration backup"
    echo "  install-tomcat - Install Tomcat 10 using platform8-setup.sh"
    echo "  help          - Show this help message"
    echo ""
    echo "Service startup order: DS → Tomcat(AM) → IDM → IG"
    echo "Service shutdown order: IG → IDM → Tomcat(AM) → DS"
}

# ========================
# Main execution logic
# ========================

# Check if script is being called with service management commands
if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

case "$1" in
    start)
        start_all_services
        ;;
    stop)
        stop_all_services
        ;;
    restart)
        restart_all_services
        ;;
    status)
        show_service_status
        ;;
    backup)
        create_backup
        ;;
    install-tomcat)
        install_tomcat
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac