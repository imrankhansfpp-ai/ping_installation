#!/bin/bash

# Determine script directory and load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/platformconfig.env"
elif [[ -f "${SCRIPT_DIR}/../platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/../platformconfig.env"
fi

# Variables
TOMCAT_VERSION="${TOMCAT_VERSION:-10.1.46}"
INSTALL_DIR="${TOMCAT_DIR:-/opt/tomcat}"
SERVICE_FILE=/etc/systemd/system/tomcat.service
TOMCAT_USER="${INSTALL_USER:-fradmin}"
TOMCAT_GROUP="${INSTALL_USER:-fradmin}"

# Detect Java Home
DETECTED_JAVA_HOME=""
if [[ -n "${JAVA_HOME:-}" && -d "${JAVA_HOME}" ]]; then
    DETECTED_JAVA_HOME="${JAVA_HOME}"
elif command -v java >/dev/null 2>&1; then
    JAVA_BIN="$(readlink -f "$(command -v java)")"
    DETECTED_JAVA_HOME="$(dirname "$(dirname "${JAVA_BIN}")")"
else
    DETECTED_JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
fi

echo "Stopping and disabling existing Tomcat service (if present)..."
sudo systemctl stop tomcat || true
sudo systemctl disable tomcat || true

echo "Removing old Tomcat from $INSTALL_DIR..."
sudo rm -rf "$INSTALL_DIR"

echo "Ensuring user '$TOMCAT_USER' exists..."
if ! id -u $TOMCAT_USER >/dev/null 2>&1; then
    sudo useradd -r -m -U -d $INSTALL_DIR -s /bin/false $TOMCAT_USER
else
    echo "User '$TOMCAT_USER' already exists."
fi

echo "Downloading Tomcat $TOMCAT_VERSION..."
cd /tmp
TARBALL_URL="https://downloads.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
ARCHIVE_URL="https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"

if ! curl -fsSL -O "$TARBALL_URL"; then
    echo "Primary download failed, attempting archive download..."
    curl -fsSL -O "$ARCHIVE_URL" || { echo "Failed to download Tomcat $TOMCAT_VERSION"; exit 1; }
fi

echo "Installing Tomcat to $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo tar xf "apache-tomcat-${TOMCAT_VERSION}.tar.gz" -C "$INSTALL_DIR" --strip-components=1

echo "Setting ownership and permissions for $TOMCAT_USER..."
sudo chown -R $TOMCAT_USER:$TOMCAT_GROUP "$INSTALL_DIR"
sudo chmod +x "$INSTALL_DIR"/bin/*.sh

echo "Creating systemd service file with ZGC and 2GB RAM allocation..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

User=$TOMCAT_USER
Group=$TOMCAT_GROUP

Environment="JAVA_HOME=$DETECTED_JAVA_HOME"
Environment="CATALINA_PID=$INSTALL_DIR/temp/tomcat.pid"
Environment="CATALINA_HOME=$INSTALL_DIR"
Environment="CATALINA_BASE=$INSTALL_DIR"
Environment="CATALINA_OPTS=-Xms256M -Xmx512M"
Environment="JAVA_OPTS=-Djava.security.egd=file:/dev/./urandom"

ExecStart=$INSTALL_DIR/bin/startup.sh
ExecStop=$INSTALL_DIR/bin/shutdown.sh

ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and starting Tomcat..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable tomcat
sudo systemctl start tomcat

echo "Tomcat installation and service setup complete with ZGC and 2GB RAM."
sudo systemctl status tomcat --no-pager
