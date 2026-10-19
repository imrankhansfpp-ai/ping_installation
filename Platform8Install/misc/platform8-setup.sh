#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: platform8-setup.sh
# Description: Setup script for Platform 8 - installs JDK 21, Tomcat 10, and
#              configures hosts file on fresh CentOS server
# Usage: ./platform8-setup.sh
################################################################################

# Load configuration (when run as misc/platform8-setup.sh from root directory)
source ./platformconfig.env

# Security: Disable bash history to prevent password exposure in command history
set +H
unset HISTFILE

# -----------------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------------
function info()    { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;32m[✔]\033[0m     $*"; }
function warning() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;33m[⚠]\033[0m     $*"; }
function error()   { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \033[1;31m[✖]\033[0m     $*"; exit 1; }

# -----------------------------------------------------------------------------
# Configuration variables
# -----------------------------------------------------------------------------
JDK_VERSION="21"
# TOMCAT_VERSION is now defined in platformconfig.env
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_ARCHIVE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TEMP_DIR="/tmp/platform8-setup"

# -----------------------------------------------------------------------------
# Hosts file configuration
# -----------------------------------------------------------------------------
function update_hosts_file() {
    info "Updating /etc/hosts with Platform 8 hostnames..."
    
    # Backup original hosts file
    if [[ ! -f /etc/hosts.backup ]]; then
        sudo cp /etc/hosts /etc/hosts.backup
        info "Created backup of original hosts file"
    fi
    
    # Define hosts entries
    local hosts_entries=(
        "127.0.0.1  am.example.com"
        "127.0.0.1  openidm.example.com"
        "127.0.0.1  idrepo1.example.com"
        "127.0.0.1  amconfig1.example.com"
        "127.0.0.1  cts1.example.com"
        "127.0.0.1  platform.example.com"
        "127.0.0.1  login.example.com"
        "127.0.0.1  admin.example.com"
        "127.0.0.1  enduser.example.com"
    )
    
    # Add entries if they don't already exist
    for entry in "${hosts_entries[@]}"; do
        local hostname=$(echo "$entry" | awk '{print $2}')
        if ! grep -q "$hostname" /etc/hosts; then
            echo "$entry" | sudo tee -a /etc/hosts > /dev/null
            info "Added: $entry"
        else
            info "Host entry already exists: $hostname"
        fi
    done
    
    success "Hosts file updated successfully"
}

# -----------------------------------------------------------------------------
# JDK 21 installation
# -----------------------------------------------------------------------------
function install_jdk21() {
    info "Installing JDK 21..."
    
    # Check if Java is already installed
    if command -v java &> /dev/null; then
        local java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
        if [[ "$java_version" =~ ^21\. ]]; then
            success "JDK 21 is already installed (version: $java_version)"
            return 0
        else
            info "Found Java version $java_version, installing JDK 21..."
        fi
    fi
    
    # Install JDK 21 using appropriate package manager
    if command -v apt-get &> /dev/null; then
        info "Installing OpenJDK 21 via apt (Ubuntu/Debian)"
        # apt-get update already run in install_prerequisites
        sudo apt-get install -y openjdk-21-jdk openjdk-21-jre-headless
    elif command -v dnf &> /dev/null; then
        # Check if this is Amazon Linux specifically
        if [[ -f /etc/os-release ]] && grep -q "ID.*amazon" /etc/os-release; then
            info "Installing Amazon Corretto 21 via dnf (Amazon Linux)"
            sudo dnf install -y java-21-amazon-corretto-devel
        else
            info "Installing OpenJDK 21 via dnf (Fedora/RHEL 8+/CentOS)"
            sudo dnf install -y java-21-openjdk java-21-openjdk-devel
        fi
    elif command -v yum &> /dev/null; then
        info "Installing OpenJDK 21 via yum (RHEL/CentOS 7)"
        # yum update already run in install_prerequisites
        sudo yum install -y java-21-openjdk java-21-openjdk-devel
    elif command -v zypper &> /dev/null; then
        info "Installing OpenJDK 21 via zypper (openSUSE/SLES)"
        # zypper refresh already run in install_prerequisites
        sudo zypper install -y java-21-openjdk java-21-openjdk-devel
    elif command -v pacman &> /dev/null; then
        info "Installing OpenJDK 21 via pacman (Arch Linux)"
        # pacman update already run in install_prerequisites
        sudo pacman -S --noconfirm jdk21-openjdk
    else
        error "No supported package manager found for JDK installation"
    fi
    
    # Set JAVA_HOME globally
    local java_home=$(dirname $(dirname $(readlink -f $(which java))))
    if [[ -d "$java_home" ]]; then
        # Set in /etc/environment for system-wide access
        echo "export JAVA_HOME=$java_home" | sudo tee /etc/environment > /dev/null
        
        # Set in current session
        export JAVA_HOME="$java_home"
        
        # Set in user profile for fradmin
        echo "export JAVA_HOME=$java_home" | sudo -u "$INSTALL_USER" tee -a "/home/$INSTALL_USER/.bashrc" > /dev/null
        
        # Set in system profile
        echo "export JAVA_HOME=$java_home" | sudo tee /etc/profile.d/java.sh > /dev/null
        sudo chmod +x /etc/profile.d/java.sh
        
        success "JAVA_HOME set globally to: $java_home"
    fi
    
    # Verify installation
    if command -v java &> /dev/null; then
        local installed_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
        success "JDK installed successfully - version: $installed_version"
    else
        error "JDK installation failed"
    fi
}

# -----------------------------------------------------------------------------
# User management
# -----------------------------------------------------------------------------
function create_install_user() {
    info "Checking/creating install user: $INSTALL_USER..."
    
    if id "$INSTALL_USER" &>/dev/null; then
        success "User $INSTALL_USER already exists"
    else
        sudo useradd -m -s /bin/bash "$INSTALL_USER"
        success "Created user: $INSTALL_USER"
    fi
    
    # Add user to necessary groups for admin privileges
    sudo usermod -a -G wheel "$INSTALL_USER" 2>/dev/null || true
    sudo usermod -a -G sudo "$INSTALL_USER" 2>/dev/null || true
    
    # Ensure the user has a proper shell environment
    sudo -u "$INSTALL_USER" bash -c "
        if [[ ! -f /home/$INSTALL_USER/.bashrc ]]; then
            cp /etc/skel/.bashrc /home/$INSTALL_USER/.bashrc 2>/dev/null || true
        fi
    "
}

function create_platform_directories() {
    info "Creating Platform 8 base directories..."
    
    # Create base installation directory with full permissions for install user
    sudo mkdir -p "$BASE_INSTALL_DIR"
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "$BASE_INSTALL_DIR"
    sudo chmod -R 755 "$BASE_INSTALL_DIR"
    
    # Create DS directory structure with full permissions
    sudo mkdir -p "$DS_DIR"
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "$DS_DIR"
    sudo chmod -R 755 "$DS_DIR"
    
    # Create IDM directory with full permissions
    sudo mkdir -p "$IDM_DIR"
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "$IDM_DIR"
    sudo chmod -R 755 "$IDM_DIR"
    
    # Create logging directory with full permissions
    sudo mkdir -p "/var/log/platform8"
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "/var/log/platform8"
    sudo chmod -R 755 "/var/log/platform8"
    
    # Create temporary directories for installation with full permissions
    sudo mkdir -p "/tmp/platform8"
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "/tmp/platform8"
    sudo chmod -R 755 "/tmp/platform8"
    
    # Give install user sudo privileges for system operations
    echo "$INSTALL_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$INSTALL_USER" > /dev/null
    
    success "Platform 8 directories created with proper ownership and permissions"
}

# -----------------------------------------------------------------------------
# Tomcat 10 installation
# -----------------------------------------------------------------------------
function check_existing_tomcat() {
    info "Checking for existing Tomcat installation..."
    
    # Check if Tomcat directory exists and has the required structure
    if [[ -d "$TOMCAT_DIR/bin" && -f "$TOMCAT_DIR/bin/catalina.sh" ]]; then
        info "Found existing Tomcat installation in $TOMCAT_DIR"
        
        # Check if it's the correct version
        if [[ -f "$TOMCAT_DIR/RELEASE-NOTES" ]]; then
            local existing_version=$(grep -E "Apache Tomcat Version" "$TOMCAT_DIR/RELEASE-NOTES" | head -n1 | awk '{print $4}' | sed 's/[^0-9.]*//g')
            if [[ "$existing_version" == "$TOMCAT_VERSION" ]]; then
                success "Tomcat $TOMCAT_VERSION already installed"
                return 0
            else
                info "Found Tomcat version $existing_version, but need version $TOMCAT_VERSION"
            fi
        fi
        
        # Check if Tomcat is running and responsive
        if systemctl is-active tomcat >/dev/null 2>&1; then
            info "Tomcat service is currently running"
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$TOMCAT_HTTP_PORT" | grep -q "200\|404"; then
                success "Existing Tomcat is working on port $TOMCAT_HTTP_PORT"
                warning "Tomcat is already installed and working. Use reinstall option if you want to replace it."
                return 0
            fi
        fi
    fi
    
    return 1
}

function download_tomcat() {
    info "Downloading Tomcat $TOMCAT_VERSION..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    if [[ -f "$TOMCAT_ARCHIVE" ]]; then
        info "Tomcat archive already exists, skipping download"
    else
        wget "$TOMCAT_URL" -O "$TOMCAT_ARCHIVE" || error "Failed to download Tomcat"
    fi
    
    success "Tomcat download completed"
}

function install_tomcat() {
    info "Installing Tomcat to $TOMCAT_DIR..."
    
    # Create TOMCAT_DIR if it doesn't exist
    sudo mkdir -p "$TOMCAT_DIR"
    
    # Extract Tomcat
    cd "$TEMP_DIR"
    tar -xzf "$TOMCAT_ARCHIVE" || error "Failed to extract Tomcat archive"
    
    # Move files to TOMCAT_DIR
    sudo cp -r "apache-tomcat-${TOMCAT_VERSION}"/* "$TOMCAT_DIR/" || error "Failed to copy Tomcat files"
    
    # Set ownership to INSTALL_USER
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "$TOMCAT_DIR" || error "Failed to set ownership"
    
    # Make scripts executable
    sudo chmod +x "$TOMCAT_DIR"/bin/*.sh
    
    success "Tomcat installation completed"
}

function configure_tomcat() {
    info "Configuring Tomcat..."
    
    # Backup original server.xml
    if [[ -f "$TOMCAT_DIR/conf/server.xml.bak" ]]; then
        info "Backup already exists, skipping backup creation"
    else
        sudo cp "$TOMCAT_DIR/conf/server.xml" "$TOMCAT_DIR/conf/server.xml.bak"
    fi
    
    # Update HTTP port in server.xml
    sudo sed -i "s/port=\"8080\"/port=\"$TOMCAT_HTTP_PORT\"/g" "$TOMCAT_DIR/conf/server.xml"
    
    # Update shutdown port to avoid conflicts
    sudo sed -i "s/port=\"8005\"/port=\"8006\"/g" "$TOMCAT_DIR/conf/server.xml"
    
    # Update AJP port to avoid conflicts
    sudo sed -i "s/port=\"8009\"/port=\"8010\"/g" "$TOMCAT_DIR/conf/server.xml"
    
    # Create setenv.sh for Java options
    local setenv_file="$TOMCAT_DIR/bin/setenv.sh"
    if [[ ! -f "$setenv_file" ]]; then
        sudo tee "$setenv_file" > /dev/null << EOF
#!/bin/bash
# Tomcat environment settings for Platform 8

# Java options
export JAVA_OPTS="\$JAVA_OPTS -Djava.awt.headless=true"
export JAVA_OPTS="\$JAVA_OPTS -Dfile.encoding=UTF-8"
export JAVA_OPTS="\$JAVA_OPTS -server"
export JAVA_OPTS="\$JAVA_OPTS -Xms256m"
export JAVA_OPTS="\$JAVA_OPTS -Xmx512m"
export JAVA_OPTS="\$JAVA_OPTS -XX:MetaspaceSize=128m"
export JAVA_OPTS="\$JAVA_OPTS -XX:MaxMetaspaceSize=256m"
export JAVA_OPTS="\$JAVA_OPTS -XX:+DisableExplicitGC"

# Platform 8 specific settings
export CATALINA_PID="\$CATALINA_BASE/logs/catalina.pid"
export CATALINA_USER="$INSTALL_USER"
EOF
        sudo chmod +x "$setenv_file"
        sudo chown "$INSTALL_USER":"$INSTALL_USER" "$setenv_file"
    fi
    
    success "Tomcat configuration completed"
}

function create_systemd_service() {
    info "Creating systemd service for Tomcat..."
    
    local service_file="/etc/systemd/system/tomcat.service"
    
    if [[ -f "$service_file" ]]; then
        info "Systemd service already exists, updating..."
    fi
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

Environment=JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
Environment=CATALINA_PID=$TOMCAT_DIR/temp/tomcat.pid
Environment=CATALINA_HOME=$TOMCAT_DIR
Environment=CATALINA_BASE=$TOMCAT_DIR
Environment='CATALINA_OPTS=-Xms256M -Xmx512M -server -XX:+UseParallelGC'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

ExecStart=$TOMCAT_DIR/bin/startup.sh
ExecStop=$TOMCAT_DIR/bin/shutdown.sh

User=$INSTALL_USER
Group=$INSTALL_USER
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable tomcat
    
    success "Systemd service created and enabled"
}

function configure_firewall() {
    info "Configuring firewall for Platform 8 services..."
    
    if command -v firewall-cmd &> /dev/null; then
        info "Disabling firewalld (RHEL/CentOS/Fedora)..."
        
        # Stop and disable firewalld
        sudo systemctl stop firewalld 2>/dev/null && \
            info "Stopped firewalld service" || \
            warning "Failed to stop firewalld service"
            
        sudo systemctl disable firewalld 2>/dev/null && \
            info "Disabled firewalld service" || \
            warning "Failed to disable firewalld service"
        
        success "Firewalld has been disabled"
        
    elif command -v ufw &> /dev/null; then
        info "Disabling UFW (Ubuntu/Debian)..."
        
        # Disable UFW
        sudo ufw --force disable 2>/dev/null && \
            success "UFW has been disabled" || \
            warning "Failed to disable UFW"
        
        # Verify UFW is disabled
        local ufw_status=$(sudo ufw status 2>/dev/null)
        if [[ "$ufw_status" =~ "Status: inactive" ]]; then
            success "UFW is now inactive"
        else
            warning "UFW status unclear: $ufw_status"
        fi
        
    else
        warning "No supported firewall found (firewalld/ufw)"
        info "No firewall changes needed"
    fi
    
    success "Firewall configuration completed - firewall is now disabled"
}

# -----------------------------------------------------------------------------
# System prerequisites
# -----------------------------------------------------------------------------
function install_prerequisites() {
    info "Installing system prerequisites..."
    
    # Detect OS and package manager
    local os_id=""
    if [[ -f /etc/os-release ]]; then
        os_id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
        info "Detected OS: $os_id"
    fi
    
    # Update system and install essential packages based on package manager
    if command -v apt-get &> /dev/null; then
        info "Using apt package manager (Ubuntu/Debian)"
        info "Updating package repositories..."
        if ! sudo apt-get update -y; then
            warning "Package update failed, but continuing with installation"
        fi
        info "Installing essential packages..."
        sudo apt-get install -y \
            wget curl tar gzip unzip \
            net-tools lsof \
            openssl libssl-dev \
            findutils \
            ufw \
            rsync \
            ca-certificates \
            gnupg \
            software-properties-common
    elif command -v dnf &> /dev/null; then
        info "Using dnf package manager (Fedora/RHEL 8+)"
        sudo dnf update -y
        sudo dnf install -y --allowerasing \
            wget curl tar gzip unzip \
            net-tools lsof \
            openssl openssl-devel \
            which findutils \
            policycoreutils-python-utils \
            firewalld \
            rsync
    elif command -v yum &> /dev/null; then
        info "Using yum package manager (RHEL/CentOS 7)"
        sudo yum update -y
        sudo yum install -y \
            wget curl tar gzip unzip \
            net-tools lsof \
            openssl openssl-devel \
            which findutils \
            policycoreutils-python-utils \
            firewalld \
            rsync
    elif command -v zypper &> /dev/null; then
        info "Using zypper package manager (openSUSE/SLES)"
        sudo zypper refresh
        sudo zypper install -y \
            wget curl tar gzip unzip \
            net-tools lsof \
            openssl openssl-devel \
            which findutils \
            firewalld \
            rsync
    elif command -v pacman &> /dev/null; then
        info "Using pacman package manager (Arch Linux)"
        sudo pacman -Syu --noconfirm
        sudo pacman -S --noconfirm \
            wget curl tar gzip unzip \
            net-tools lsof \
            openssl \
            which findutils \
            firewalld \
            rsync
    else
        error "No supported package manager found (apt, dnf, yum, zypper, pacman)"
    fi
    
    # Note: Firewall will be disabled in configure_firewall function
    if command -v firewall-cmd &> /dev/null; then
        info "firewalld detected - will be disabled later for Platform 8"
    elif command -v ufw &> /dev/null; then
        info "UFW detected - will be disabled later for Platform 8"
    else
        info "No supported firewall found (firewalld/ufw)"
    fi
    
    success "System prerequisites installed"
}

# -----------------------------------------------------------------------------
# Testing functions
# -----------------------------------------------------------------------------
function test_tomcat() {
    info "Testing Tomcat installation..."
    
    # Start Tomcat and leave it running
    sudo systemctl start tomcat
    sleep 15
    
    # Check if Tomcat is running
    if sudo systemctl is-active tomcat >/dev/null; then
        success "Tomcat is running successfully"
        
        # Test HTTP connectivity
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$TOMCAT_HTTP_PORT" | grep -q "200\|404"; then
            success "Tomcat is responding on port $TOMCAT_HTTP_PORT"
        else
            warning "Tomcat may not be responding correctly on port $TOMCAT_HTTP_PORT"
        fi
        
        # Leave Tomcat running for Platform 8 installation
        info "Tomcat is running and ready for Platform 8 installation"
    else
        error "Tomcat failed to start"
    fi
}

function cleanup() {
    info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    success "Cleanup completed"
}

# -----------------------------------------------------------------------------
# Platform 8 installation functions
# -----------------------------------------------------------------------------
function run_platform_installation() {
    info "Starting Platform 8 installation as user: $INSTALL_USER..."
    
    # Check if the main platform installation script exists
    local platform_install_script="./bin/install_platform8.sh"
    if [[ ! -f "$platform_install_script" ]]; then
        # Try alternative path if we're running from the bin directory
        platform_install_script="../bin/install_platform8.sh"
        if [[ ! -f "$platform_install_script" ]]; then
            platform_install_script="./install_platform8.sh"
            if [[ ! -f "$platform_install_script" ]]; then
                warning "Platform 8 installation script not found in expected locations"
                info "Looked for: ./bin/install_platform8.sh, ../bin/install_platform8.sh, ./install_platform8.sh"
                info "Skipping platform installation - run manually after setup completes"
                return 0
            fi
        fi
    fi
    
    # Ensure the install user has access to the current directory and scripts
    local current_dir="$(pwd)"
    
    # Create temporary backup of original ownership for critical system files
    info "Setting up permissions for user $INSTALL_USER..."
    
    # Only change ownership of the project directory and its contents
    sudo chown -R "$INSTALL_USER":"$INSTALL_USER" "$current_dir"
    
    # Ensure the platform install script is executable
    sudo chmod +x "$platform_install_script"
    
    # Copy environment configuration to install user's home directory with secure permissions
    sudo -u "$INSTALL_USER" cp "$current_dir/platformconfig.env" "/home/$INSTALL_USER/"
    sudo -u "$INSTALL_USER" chmod 600 "/home/$INSTALL_USER/platformconfig.env"
    
    info "Switching to user $INSTALL_USER to run platform installation..."
    
    # Run the platform installation as the install user
    sudo -u "$INSTALL_USER" bash -c "
        cd '$current_dir'
        source ./platformconfig.env
        export JAVA_HOME=\$(dirname \$(dirname \$(readlink -f \$(which java))))
        
        # Disable bash history to prevent password exposure in command history
        set +H
        unset HISTFILE
        
        if [[ -f '$platform_install_script' ]]; then
            echo 'Running Platform 8 installation as $INSTALL_USER...'
            bash '$platform_install_script'
        else
            echo 'Platform installation script not found: $platform_install_script'
            exit 1
        fi
    "
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        success "Platform 8 installation completed successfully as user: $INSTALL_USER"
    else
        error "Platform 8 installation failed with exit code: $exit_code"
    fi
}

# -----------------------------------------------------------------------------
# Main setup function
# -----------------------------------------------------------------------------
function setup_prerequisites() {
    info "Starting Platform 8 prerequisites setup..."
    
    # Detect and display OS information
    local os_info=""
    if [[ -f /etc/os-release ]]; then
        local os_name=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
        local os_version=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d '"')
        os_info="$os_name $os_version"
        info "Detected OS: $os_info"
    fi
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        info "Package manager: apt (Ubuntu/Debian)"
    elif command -v dnf &> /dev/null; then
        info "Package manager: dnf (Fedora/RHEL 8+)"
    elif command -v yum &> /dev/null; then
        info "Package manager: yum (RHEL/CentOS 7)"
    elif command -v zypper &> /dev/null; then
        info "Package manager: zypper (openSUSE/SLES)"
    elif command -v pacman &> /dev/null; then
        info "Package manager: pacman (Arch Linux)"
    fi
    
    info "This script will configure all prerequisites for Platform 8:"
    info "  1. Update /etc/hosts with Platform 8 hostnames"
    info "  2. Install JDK 21"
    info "  3. Create install user: $INSTALL_USER"
    info "  4. Create Platform 8 base directories with proper ownership"
    info "  5. Install and configure Tomcat 10"
    info "  6. Configure systemd service for Tomcat"
    info "  7. Install additional system packages"
    info ""
    
    read -p "Continue with Platform 8 prerequisites setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Prerequisites setup cancelled"
        exit 0
    fi
    
    install_prerequisites
    update_hosts_file
    install_jdk21
    create_install_user
    create_platform_directories
    if ! check_existing_tomcat; then
        download_tomcat
        install_tomcat
        configure_tomcat
        create_systemd_service
        test_tomcat
        cleanup
    fi
    # Always configure firewall (even if Tomcat already exists)
    configure_firewall
    
    success "Platform 8 prerequisites setup completed successfully!"
    echo ""
    info "Prerequisites Summary:"
    info "  - System packages installed and updated"
    info "  - JDK 21 installed and configured"
    info "  - Install user created: $INSTALL_USER"
    info "  - Platform 8 directories created: $BASE_INSTALL_DIR, $DS_DIR, $IDM_DIR"
    info "  - Logging directory created: /var/log/platform8"
    info "  - Tomcat 10 installed in: $TOMCAT_DIR"
    info "  - Tomcat configured to run on port: $TOMCAT_HTTP_PORT"
    info "  - Systemd service created: tomcat.service"
    info "  - Hosts file updated with Platform 8 hostnames"
    info "  - Firewall disabled for Platform 8"
    info "  - JAVA_HOME set globally for all users"
    info "  - Install user granted sudo privileges"
    echo ""
    success "Operating System is now ready for Platform 8 installation!"
    echo ""
    info "🚀 NEXT STEP: Install Platform 8 components"
    info "   Run the following command to install Platform 8:"
    info "   ./bin/install_platform8.sh"
    echo ""
    info "📊 System monitoring:"
    info "  - Check Tomcat status: sudo systemctl status tomcat"
    info "  - View logs: sudo journalctl -u tomcat -f"
    info "  - Access Tomcat: http://localhost:$TOMCAT_HTTP_PORT"
}

function setup_and_install_platform() {
    info "Starting complete Platform 8 setup and installation..."
    
    # Detect and display OS information
    if [[ -f /etc/os-release ]]; then
        local os_name=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
        local os_version=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d '"')
        info "Detected OS: $os_name $os_version"
    fi
    
    info "This script will:"
    info "  1. Set up all prerequisites (JDK, Tomcat, user, directories)"
    info "  2. Run the full Platform 8 installation as user: $INSTALL_USER"
    info ""
    
    read -p "Continue with complete Platform 8 setup and installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Setup and installation cancelled"
        exit 0
    fi
    
    # First run all prerequisites
    install_prerequisites
    update_hosts_file
    install_jdk21
    create_install_user
    create_platform_directories
    if ! check_existing_tomcat; then
        download_tomcat
        install_tomcat
        configure_tomcat
        create_systemd_service
        test_tomcat
        cleanup
    fi
    # Always configure firewall (even if Tomcat already exists)
    configure_firewall
    
    success "Prerequisites setup completed! Now running Platform 8 installation..."
    echo ""
    
    # Then run the platform installation as the install user
    run_platform_installation
    
    success "Complete Platform 8 setup and installation finished!"
    echo ""
    info "Installation Summary:"
    info "  - All system prerequisites configured"
    info "  - Platform 8 installed and configured as user: $INSTALL_USER"
    info "  - Services should be running and accessible"
    echo ""
    info "SECURITY NOTE: Passwords are hidden in logs for security."
    info "Default credentials are stored in platformconfig.env - change default passwords before production use."
    echo ""
    info "Access Information:"
    info "  - AM Console: http://${AM_HOSTNAME:-am.example.com}:${TOMCAT_HTTP_PORT:-8081}/am/console"
    info "  - IDM Admin UI: http://${IDM_HOSTNAME:-openidm.example.com}:8080/admin/"
    info "  - Default admin username: amadmin (AM), openidm-admin (IDM)"
    info "  - Default password: [HIDDEN] - check platformconfig.env file"
}

# -----------------------------------------------------------------------------
# Command line interface
# -----------------------------------------------------------------------------
function show_usage() {
    echo "Platform 8 Operating System Prerequisites Setup Script"
    echo "Usage: $0 [command]"
    echo ""
    echo "PURPOSE:"
    echo "  This script prepares your operating system for Platform 8 installation by"
    echo "  setting up prerequisites like JDK 21, Tomcat 10, users, directories, and"
    echo "  system configuration. It does NOT install Platform 8 components."
    echo ""
    echo "Commands:"
    echo "  all           - Setup all Platform 8 prerequisites (default)"
    echo "  prerequisites - Setup all Platform 8 prerequisites"
    echo "  hosts         - Update hosts file only"
    echo "  jdk           - Install JDK 21 only"
    echo "  tomcat        - Install Tomcat 10 only"
    echo "  firewall      - Configure firewall only"
    echo "  test          - Test Tomcat installation"
    echo "  help          - Show this help message"
    echo ""
    echo "AFTER RUNNING THIS SCRIPT:"
    echo "  Run './bin/install_platform8.sh' to install Platform 8 components"
    echo ""
    echo "NOTE: This script creates the '$INSTALL_USER' user with admin privileges"
    echo "      for running the Platform 8 installation."
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
case "${1:-all}" in
    all|prerequisites)
        setup_prerequisites
        ;;
    hosts)
        update_hosts_file
        ;;
    jdk)
        install_prerequisites
        install_jdk21
        ;;
    tomcat)
        install_prerequisites
        create_install_user
        if ! check_existing_tomcat; then
            download_tomcat
            install_tomcat
            configure_tomcat
            create_systemd_service
            test_tomcat
            cleanup
        fi
        # Always configure firewall (even if Tomcat already exists)
        configure_firewall
        ;;
    test)
        test_tomcat
        ;;
    firewall)
        configure_firewall
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