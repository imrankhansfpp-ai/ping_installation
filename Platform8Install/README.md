# Platform 8 Installation Suite

**Author:** Mark Nienaber
**Last Updated:** May 2026

## Overview

This repository contains an installation suite for Ping Identity's Platform 8. It provides automated deployment and configuration scripts for the full identity and access management stack: Directory Services (DS), Access Management (AM), Identity Management (IDM), Identity Gateway (IG), and Platform UI.

The scripts detect product versions automatically from the binaries placed in the `software/` directories, so you can drop in any supported Platform 8 release without editing the scripts.

## Architecture Components

The installation suite manages the following core components.

### Directory Services (DS)
- LDAP directory server for identity data storage
- Consolidated Single Instance hosting all platform profiles in one process:
  - Identity Repository (`am-identity-store:8.0.0` & `idm-repo`)
  - Core Token Service (`am-cts`)
  - Configuration Store (`am-config`)
- Saves ~2.5 GB of RAM compared to running 3 separate DS instances.

### 2-Server Topology & Memory Optimization (For 8GB RAM Servers)
When running on 8GB RAM servers, components are split cleanly into two tiers with memory limited to 512MB per component:
- **Server 1 (Data & Identity Tier)**: Consolidated DS + PingIDM
- **Server 2 (Access & Edge Tier)**: Apache Tomcat (PingAM + Platform UI) + PingGateway (IG)
- Run `./install_server1.sh` on Server 1 and `./install_server2.sh` on Server 2.

### Access Management (AM)
- Authentication and authorization server
- Deployment options:
  - File Based Configuration (FBC) mode
  - DS based configuration mode
- Features: authentication trees, OAuth2 / OIDC, SAML

### Identity Management (IDM)
- Identity lifecycle management and user self service
- Capabilities: user provisioning, workflow, compliance

### Identity Gateway (IG)
- Reverse proxy and API gateway
- Functions: authentication enforcement, request and response transformation

### Platform UI
- Web based user interfaces
- Components: admin console, end user portal, login pages

## Project Structure

```
Platform8Install/
├── install_platform8.sh          # Main orchestration script
├── platformconfig.env            # Central configuration file
├── am/                           # Access Management components
│   ├── am8.sh                    # AM DS based deployment
│   ├── am8fbc.sh                 # AM FBC deployment
│   ├── configure_am.sh           # REST based configuration
│   ├── setenv.sh                 # Environment setup (DS mode)
│   ├── setenv-fbc.sh             # Environment setup (FBC mode)
│   └── root/                     # Authentication trees and nodes
├── ds/                           # Directory Services
│   ├── ds8.sh                    # DS installation script
│   └── configure_disk_thresholds.sh  # Lower DS disk thresholds for dev
├── idm/                          # Identity Management
│   ├── idm8.sh                   # IDM deployment script
│   ├── *.json                    # Configuration files
│   └── resolver/                 # Boot properties
├── ig/                           # Identity Gateway
│   ├── ig8.sh                    # IG deployment script
│   ├── *.json                    # Gateway configuration
│   └── routes/                   # Route definitions
├── ui/                           # Platform UI
│   └── platformui.sh             # UI deployment script
├── misc/                         # Utilities and tools
│   ├── platform8-setup.sh        # Server prerequisites installer
│   ├── platform8-control.sh      # Start / stop / status helper
│   ├── manage-ds.sh              # DS management utilities
│   ├── updatejava21.sh           # Java 21 update script
│   ├── updatetomcat10.sh         # Tomcat 10 update script
│   └── keys/                     # SSH keys and certificates
└── software/                     # Installation binaries
    ├── am/                       # AM and Amster files
    ├── ds/                       # DS file
    ├── idm/                      # IDM file
    ├── ig/                       # PingGateway file
    └── ui/                       # Platform UI file
```

## Prerequisites

### System Requirements
- Operating System: Linux (tested on Amazon Linux) or macOS
- Java: OpenJDK 21
- Apache Tomcat 10.x (the version installed by the setup script is set in `platformconfig.env` via `TOMCAT_VERSION`)
- Memory: 16 GB RAM recommended
- Storage: 20 GB free space

### Required Software Binaries

Place the Ping Identity software files into the matching `software/` subdirectories. The scripts find files by name pattern, so version numbers in filenames are detected automatically.

```
software/
├── am/
│   ├── AM-<version>.war
│   └── Amster-<version>.zip
├── ds/
│   └── DS-<version>.zip
├── idm/
│   └── IDM-<version>.zip
├── ig/
│   └── PingGateway-<version>.zip
└── ui/
    └── PlatformUI-<version>.zip
```

File name patterns used by the scripts:

| Component | Pattern               |
|-----------|-----------------------|
| AM        | `AM*.war`             |
| Amster    | `Amster-*.zip`        |
| DS        | `DS*.zip`             |
| IDM       | `IDM*.zip`            |
| IG        | `PingGateway*.zip`    |
| UI        | `PlatformUI*.zip`     |

If more than one matching file is present in a directory the first match is used. Keep only the version you want to install in each folder.

### Network Configuration

Ensure the following hostnames resolve to the install host. Add them to `/etc/hosts` if needed:

```
127.0.0.1   am.example.com
127.0.0.1   openidm.example.com
127.0.0.1   platform.example.com
127.0.0.1   login.example.com
127.0.0.1   admin.example.com
127.0.0.1   enduser.example.com
127.0.0.1   cts1.example.com
127.0.0.1   amconfig1.example.com
127.0.0.1   idrepo1.example.com
```

The `misc/platform8-setup.sh` script can populate these entries for you.

## Installation

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/mark-nienaber/Platform8Install.git
   cd Platform8Install
   ```

2. **Place software binaries** in the matching `software/` subdirectories.

3. **Create the install user:**
   ```bash
   sudo useradd -m -s /bin/bash fradmin
   sudo usermod -aG sudo fradmin
   sudo su - fradmin
   cd /path/to/Platform8Install
   ```

4. **Make all scripts executable:**
   ```bash
   find . -name "*.sh" -type f -exec chmod +x {} +
   ```

5. **Review configuration:**
   ```bash
   vim platformconfig.env
   ```
   Confirm `INSTALL_USER` matches the user you created and update hostnames or passwords if you need different values.

6. **Run server prerequisites (first time only):**
   ```bash
   ./misc/platform8-setup.sh
   ```
   This installs JDK 21, Tomcat 10, sets up directories, host entries, and firewall rules.

7. **Run installation:**
   ```bash
   ./install_platform8.sh
   ```

8. **Select configuration mode when prompted:**
   - Enter `1` for File Based Configuration (FBC) mode
   - Enter `2` for DS based configuration mode

### Installation Process

The orchestrator runs these steps in order.

1. **Stop IDM** if running.
2. **Cleanup AM** removes any prior AM installation artifacts.
3. **Configure DS** sets up the directory service instances and lowers disk thresholds for development environments.
4. **Deploy AM** with the chosen configuration mode (FBC or DS).
5. **Deploy IDM** and configure identity management services.
6. **Deploy IG** with platform routes.
7. **Configure AM** by applying REST based configuration (creates the `idm-provisioning` OAuth2 client and other settings).
8. **Deploy UI** for admin, login, and end user portals.
9. **Create test users** in IDM via the `idm-provisioning` OAuth2 client (alpha realm). Skipped when `INSTALL_TEST_USERS=false` or `TEST_USER_COUNT<=0`.

## Configuration

### Core Configuration File

The `platformconfig.env` file contains all deployment parameters. Common values you may want to change:

```bash
INSTALL_USER="fradmin"                   # Installation user
DEFAULT_PASSWORD="password"              # Default admin password
DS_ADMIN_PASSWORD="password"             # cn=Directory Manager password
LDAP_BIND_PASSWORD="password"            # LDAP service bind password
AM_HOSTNAME="am.example.com"             # AM server hostname
IDM_HOSTNAME="openidm.example.com"       # IDM server hostname
IG_HOSTNAME="platform.example.com"       # IG hostname
COOKIE_DOMAIN="example.com"              # Session cookie domain
TOMCAT_VERSION="10.1.46"                 # Tomcat version installed by setup script

# Test users (Step 9)
INSTALL_TEST_USERS=true
TEST_USER_COUNT=5
TEST_USER_PASSWORD='!@34QWer'
```

Software versions are no longer set in `platformconfig.env`. Each component script detects the version from the binary present in its `software/` subdirectory.

### Port Configuration

| Component | HTTP Port | HTTPS Port | Admin Port |
|-----------|-----------|------------|------------|
| AM        | 8081      | -          | -          |
| IDM       | 8080      | 8553       | 9444       |
| IG        | 7080      | 9443       | -          |
| DS (All)  | 18081     | 18443      | 14444      |
| UI Admin  | 8082      | -          | -          |
| UI Login  | 8083      | -          | -          |
| UI EndUser| 8888      | -          | -          |

## Usage

### Access URLs

After a successful installation, access the platform via the gateway:

- **Platform Gateway:** https://platform.example.com:9443

### Default Credentials

- **Username:** `amadmin`
- **Password:** value of `DEFAULT_PASSWORD` in `platformconfig.env`

### Test Users

When Step 9 runs, it creates `testuser1` through `testuser${TEST_USER_COUNT}` in the alpha realm with password `${TEST_USER_PASSWORD}`. Existing users with the same name are left alone.

### Component Scripts

> All scripts must be run from the repository root (`Platform8Install/`) because they read `platformconfig.env` and use relative paths.

```bash
# Individual component deployment
./ds/ds8.sh              # Deploy DS
./am/am8.sh              # Deploy AM (DS mode)
./am/am8fbc.sh           # Deploy AM (FBC mode)
./idm/idm8.sh            # Deploy IDM
./ig/ig8.sh              # Deploy IG
./ui/platformui.sh       # Deploy UI
./am/configure_am.sh     # Apply REST based AM configuration
```

Example:

```bash
# Correct: from the repo root
cd Platform8Install
./am/am8fbc.sh

# Incorrect: this will not find platformconfig.env
cd Platform8Install/am
./am8fbc.sh
```

### Helper Scripts

```bash
./misc/platform8-setup.sh           # Install JDK 21, Tomcat 10, host entries
./misc/platform8-control.sh         # Start, stop, or status of platform services
./misc/manage-ds.sh                 # Common DS management tasks
./misc/updatejava21.sh              # Update Java to OpenJDK 21
./misc/updatetomcat10.sh            # Update Tomcat to the version in TOMCAT_VERSION
./ds/configure_disk_thresholds.sh   # Lower DS disk thresholds for dev hosts
```

## Authentication Trees

The installation includes pre configured authentication trees:

- **PlatformLogin** standard username and password authentication
- **PlatformRegistration** user self registration
- **PlatformResetPassword** password reset flow
- **PlatformProgressiveProfile** progressive profiling
- **Google-DynamicAccountCreation** social login with account creation
- **Facebook-ProvisionIDMAccount** Facebook social authentication

## Troubleshooting

### Common Issues

1. **Port conflicts**
   - Check if a required port is in use: `netstat -tulpn | grep :8081`
   - Adjust the port in `platformconfig.env`

2. **Hostname resolution**
   - Verify `/etc/hosts` entries
   - Test with `ping am.example.com`

3. **Permission issues**
   - Ensure scripts are executable: `chmod +x *.sh`
   - Run as the user defined by `INSTALL_USER`

4. **Software binary issues**
   - Confirm the expected file is present in each `software/` subdirectory
   - Confirm only one matching file per directory so the right version is picked up

5. **Test users not created**
   - Step 9 needs the `idm-provisioning` OAuth2 client created in Step 7. If Step 7 failed, the test users will fail too.
   - Check that AM is reachable on `${AM_URL}` and IDM is up on `${IDM_HOSTNAME}:${BOOT_PORT_HTTP}`.

### Log Locations

- **AM logs:** `${TOMCAT_DIR}/logs/catalina.out`
- **IDM logs:** `${IDM_EXTRACT_DIR}/logs/openidm*.log`
- **DS logs:** `${DS_DIR}/*/logs/errors`
- **IG logs:** `${IG_DIR}/logs/`

### Cleanup and Reinstall

To reinstall, just rerun the installer. It stops IDM and removes prior AM artifacts before redeploying.

```bash
./install_platform8.sh
```

For a deeper reset, remove the install directories under `${BASE_INSTALL_DIR}` (default `/ping`) and the Tomcat webapps before rerunning.

## License

This project is provided as is for Ping Identity platform deployment automation. Refer to Ping Identity licensing for individual component usage rights.

---

**Note:** This installation suite is designed for development and testing environments. Additional hardening and configuration is required for production deployments.
