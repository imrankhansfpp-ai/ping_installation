# Ping Identity Platform 8 Installation & Deployment Suite

**Author:** PATHAN IMRAN KHAN  
**Architecture:** Multi-Server (2-Server Tiered) & Single-Server All-in-One  
**Stack:** Directory Services (DS 8.x), Access Management (AM 8.x), Identity Management (IDM 8.x), Identity Gateway (IG 2024.x/2025.x), Platform UI  
**Target Host Specifications:** Minimum 8 GB RAM per host (tuned with 512MB JVM heap limits per component)

---

## 1. Overview & Architecture

This repository provides an enterprise-ready, automated installation suite for Ping Identity's Platform 8 stack. It automatically deploys, configures, interconnects, and hardens the complete identity fabric:

- **Consolidated Directory Services (DS 8.x):** A single high-performance LDAP instance hosting all platform profiles (**AM Identity Store**, **Core Token Service CTS**, **AM Configuration Store**, and **IDM Repository**), saving **~2.5 GB of RAM** compared to running separate DS processes.
- **Access Management (AM 8.x):** Advanced identity and access management deployed on Apache Tomcat 10, supporting File-Based Configuration (FBC) or DS-based configuration with out-of-the-box authentication journeys.
- **Identity Management (IDM 8.x):** Identity lifecycle management, user self-service, provisioning, and workflow engine connected securely via LDAPS to the consolidated identity store.
- **Identity Gateway (IG 2024.x / 2025.x):** Reverse proxy and API gateway providing TLS termination, session enforcement, and unified edge routing.
- **Platform UI:** Modern Admin, Login, and End-User web interfaces.
- **Dynamic Binary Auto-Detection:** Product versions are automatically discovered from filenames in `software/` directories (e.g. `DS*.zip`, `AM*.war`, `IDM*.zip`, `PingGateway*.zip`, `PlatformUI*.zip`). You can drop in any version without editing scripts.

---

## 2. Deployment Topologies

### Topology A: 2-Server Distributed Architecture (Recommended for 8GB RAM Servers)

In an 8GB RAM environment, running all components on a single host causes memory pressure. The 2-Server topology cleanly isolates stateful data services from edge web services:

```
┌──────────────────────────────────────────────────────────────┐
│ CLIENT / BROWSER                                             │
└──────────────────────────────┬───────────────────────────────┘
                               │ HTTPS (9443)
                               ▼
┌──────────────────────────────────────────────────────────────┐
│ SERVER 2: Access & Edge Tier (e.g. 10.0.1.20)                │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ PingGateway (IG) - Reverse Proxy / TLS Gateway (9443)  │  │
│  └──────────┬─────────────────────────────┬───────────────┘  │
│             │ HTTP (8081)                 │ HTTP (8082-8888) │
│             ▼                             ▼                  │
│  ┌────────────────────────┐  ┌────────────────────────────┐  │
│  │ Apache Tomcat 10:      │  │ Platform UI:               │  │
│  │ PingAM (am.war)        │  │ Admin / EndUser / Login    │  │
│  └──────────┬─────────────┘  └────────────────────────────┘  │
└─────────────┼────────────────────────────────────────────────┘
              │ LDAPS (1636) - TLS with ds-ca-cert.pem
              ▼
┌──────────────────────────────────────────────────────────────┐
│ SERVER 1: Data & Identity Tier (e.g. 10.0.1.10)              │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Consolidated Directory Services (DS)                   │  │
│  │  - Identity Store (amIdentityStore & idmRepo)          │  │
│  │  - Core Token Service (amCts)                          │  │
│  │  - Configuration Store (cfgStore)                      │  │
│  │  LDAPS Port: 1636 | LDAP Port: 1389 | Admin: 14444     │  │
│  └──────────▲─────────────────────────────────────────────┘  │
│             │ LDAPS (1636) / localhost                       │
│  ┌──────────┴─────────────┐                                  │
│  │ PingIDM (openidm)      │                                  │
│  │ HTTP Port: 8080        │                                  │
│  └────────────────────────┘                                  │
└──────────────────────────────────────────────────────────────┘
```

- **Server 1 (Data & Identity Tier):** Runs **Consolidated DS** + **PingIDM**.
- **Server 2 (Access & Edge Tier):** Runs **Tomcat 10 (PingAM + UI)** + **PingGateway (IG)**.

### Topology B: Single-Server All-in-One Architecture

For servers with **16 GB+ RAM** or development sandboxes, all services run on a single host (`SERVER1_IP=127.0.0.1` and `SERVER2_IP=127.0.0.1`).

---

## 3. Network Ports & Firewall Requirements

Ensure the following ports are open and accessible between the servers:

| Tier | Component | Port | Protocol | Purpose / Access Required |
|------|-----------|------|----------|---------------------------|
| **Server 1** | Consolidated DS | `1636` | LDAPS / TCP | **CRITICAL:** Accessed by Server 2 (AM/Amster) and Server 1 (IDM) |
| **Server 1** | Consolidated DS | `1389` | LDAP / TCP | Cleartext LDAP port (internal / optional) |
| **Server 1** | Consolidated DS | `14444` | Admin / TCP | DS Administration Connector (`dsconfig`) |
| **Server 1** | Consolidated DS | `18081` / `18443` | HTTP/HTTPS | DS REST monitoring endpoints |
| **Server 1** | PingIDM | `8080` | HTTP / TCP | IDM REST API (accessed by Server 2 / AM provisioning) |
| **Server 1** | PingIDM | `8553` | HTTPS / TCP | IDM secure port |
| **Server 2** | PingGateway (IG) | `9443` | HTTPS / TCP | **Public / User Access:** Gateway HTTPS entry point |
| **Server 2** | PingGateway (IG) | `7080` | HTTP / TCP | Gateway internal HTTP port |
| **Server 2** | Apache Tomcat 10 | `8081` | HTTP / TCP | AM application context (`/am`) |
| **Server 2** | Platform UI | `8082` | HTTP / TCP | UI Admin portal (`/admin`) |
| **Server 2** | Platform UI | `8083` | HTTP / TCP | UI Login portal (`/login`) |
| **Server 2** | Platform UI | `8888` | HTTP / TCP | UI End-User portal (`/enduser`) |

### Firewall Configuration (firewalld)

**On Server 1:**
```bash
sudo firewall-cmd --permanent --add-port=1636/tcp
sudo firewall-cmd --permanent --add-port=1389/tcp
sudo firewall-cmd --permanent --add-port=14444/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

**On Server 2:**
```bash
sudo firewall-cmd --permanent --add-port=9443/tcp
sudo firewall-cmd --permanent --add-port=8081/tcp
sudo firewall-cmd --permanent --add-port=8082/tcp
sudo firewall-cmd --permanent --add-port=8083/tcp
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --reload
```

---

## 4. Required Software Binaries & Placement

Obtain the Platform 8 distribution packages from the Ping Identity BackStage portal and place them into the respective `software/` directories.

### Server 1 Software Directory (`software/`)
Server 1 only requires the Directory Services and Identity Management binaries:
```
software/
├── ds/
│   └── DS-8.0.0.zip          # Matches pattern: DS*.zip
└── idm/
    └── IDM-8.0.0.zip         # Matches pattern: IDM*.zip
```

### Server 2 Software Directory (`software/`)
Server 2 requires Access Management, Amster, Identity Gateway, and Platform UI:
```
software/
├── am/
│   ├── AM-8.0.1.war          # Matches pattern: AM*.war
│   └── Amster-8.0.1.zip      # Matches pattern: Amster-*.zip
├── ig/
│   └── PingGateway-2024.11.0.zip  # Matches pattern: PingGateway*.zip
└── ui/
    └── PlatformUI-8.0.0.zip   # Matches pattern: PlatformUI*.zip
```

*(Note: For Single-Server installations, place all 6 files into their respective subdirectories).*

---

## 5. Pre-Requisites & OS Preparation (Both Servers)

Perform these steps on **both** Server 1 and Server 2 before beginning the installation.

### Step 1: Install Operating System Utilities
Ensure standard administrative tools are installed:

- **RHEL / Rocky Linux / AlmaLinux / CentOS / Amazon Linux 2023:**
  ```bash
  sudo dnf install -y curl unzip tar net-tools iproute jq python3 openssl
  ```
- **Debian / Ubuntu:**
  ```bash
  sudo apt-get update && sudo apt-get install -y curl unzip tar net-tools iproute2 jq python3 openssl
  ```

### Step 2: Create the Platform Service User
A dedicated non-root user (`fradmin`) must own and execute the platform components:

```bash
sudo useradd -m -s /bin/bash fradmin
echo "fradmin ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/fradmin
sudo chmod 0440 /etc/sudoers.d/fradmin
```

### Step 3: Configure Hostname Resolution (`/etc/hosts`)
Proper FQDN resolution is **mandatory** for PKI certificate validation, cookies, and cross-tier communication.

Assume:
- Server 1 IP = `10.0.1.10`
- Server 2 IP = `10.0.1.20`

Add the following block to `/etc/hosts` on **BOTH** Server 1 and Server 2:

```text
# --- Ping Platform 8 Hosts ---
10.0.1.10   ds1.example.com openidm.example.com cts1.example.com amconfig1.example.com idrepo1.example.com
10.0.1.20   platform.example.com am.example.com login.example.com admin.example.com enduser.example.com
```

*(For Single-Server setups, use `127.0.0.1` instead of `10.0.1.10` / `10.0.1.20`).*

---

## 6. Step-by-Step Installation: 2-Server Topology

### Phase 1: Install Server 1 (Data & Identity Tier)

Run all steps on **Server 1** as the `fradmin` user.

#### 1. Clone or Copy the Repository
```bash
sudo su - fradmin
cd ~
git clone https://github.com/mark-nienaber/Platform8Install.git
cd Platform8Install
find . -name "*.sh" -type f -exec chmod +x {} +
```

#### 2. Place Server 1 Binaries
Ensure the following files are present:
- `software/ds/DS*.zip`
- `software/idm/IDM*.zip`

#### 3. Configure `platformconfig.env`
Edit `platformconfig.env`:
```bash
nano platformconfig.env
```
Ensure the IP configuration reflects your network:
```bash
SERVER1_IP="10.0.1.10"                # IP address of Server 1
SERVER2_IP="10.0.1.20"                # IP address of Server 2
SERVER1_HOSTNAME="ds1.example.com"
SERVER2_HOSTNAME="platform.example.com"
INSTALL_USER="fradmin"
DEFAULT_PASSWORD="password"           # Admin password
DS_ADMIN_PASSWORD="password"          # Directory Manager password
```

#### 4. Run System Prerequisites Setup
```bash
./misc/platform8-setup.sh
```
This script installs OpenJDK 21, sets up base directories under `/ping`, configures hosts, and adjusts system limits.

#### 5. Execute Server 1 Installation
```bash
./install_server1.sh
```
*Alternatively, run `./install_platform8.sh` and select option `2`.*

The script will automatically:
1. Stop any residual IDM processes.
2. Deploy Consolidated Directory Services (DS) with all 4 profiles (512MB heap).
3. Lower disk write thresholds to prevent low-disk development freezes.
4. Deploy and start PingIDM (512MB heap) connecting over LDAPS to DS.
5. Export the DS CA Certificate to `./misc/keys/ds-ca-cert.pem`.

#### 6. Verify Server 1
Check that all Server 1 services are running:
```bash
./misc/platform8-control.sh status
```
Verify DS listening ports:
```bash
ss -tulpn | grep -E '1636|8080'
```

#### 7. Transfer DS CA Certificate to Server 2
The Access Management tier on Server 2 requires the DS CA certificate to establish secure LDAPS connections during installation:

```bash
# Copy directly to Server 2's Platform8Install directory:
scp ./misc/keys/ds-ca-cert.pem fradmin@10.0.1.20:~/Platform8Install/misc/keys/
```

---

### Phase 2: Install Server 2 (Access & Edge Tier)

Run all steps on **Server 2** as the `fradmin` user.

#### 1. Clone or Copy the Repository
```bash
sudo su - fradmin
cd ~
git clone https://github.com/mark-nienaber/Platform8Install.git
cd Platform8Install
find . -name "*.sh" -type f -exec chmod +x {} +
mkdir -p misc/keys
```

#### 2. Place Server 2 Binaries
Ensure the following files are present:
- `software/am/AM*.war`
- `software/am/Amster-*.zip`
- `software/ig/PingGateway*.zip`
- `software/ui/PlatformUI*.zip`

#### 3. Configure `platformconfig.env`
Edit `platformconfig.env` with **identical** settings to Server 1:
```bash
nano platformconfig.env
```
Ensure:
```bash
SERVER1_IP="10.0.1.10"                # IP address of Server 1
SERVER2_IP="10.0.1.20"                # IP address of Server 2
SERVER1_HOSTNAME="ds1.example.com"
SERVER2_HOSTNAME="platform.example.com"
INSTALL_USER="fradmin"
DEFAULT_PASSWORD="password"           # Must match Server 1
DS_ADMIN_PASSWORD="password"          # Must match Server 1
```

#### 4. Verify DS CA Certificate on Server 2
Confirm that `ds-ca-cert.pem` was copied into `misc/keys/`:
```bash
ls -l ./misc/keys/ds-ca-cert.pem
```
*(If missing, copy it from Server 1 using `scp` as described in Phase 1 Step 7).*

#### 5. Verify Network Connectivity to Server 1
Test that Server 2 can reach Server 1 over LDAPS:
```bash
openssl s_client -connect ds1.example.com:1636 -showcerts </dev/null
```
If connection succeeds, proceed.

#### 6. Run System Prerequisites Setup (Tomcat & Java 21)
```bash
./misc/platform8-setup.sh
```
This script installs OpenJDK 21, Apache Tomcat 10, sets up directory structures, and configures host entries.

#### 7. Execute Server 2 Installation
```bash
./install_server2.sh
```
*Alternatively, run `./install_platform8.sh` and select option `3`.*

The script will automatically:
1. Run preflight checks for all 4 software binaries.
2. Verify network connectivity to `ds1.example.com:1636`.
3. Import `ds-ca-cert.pem` into Java's truststore and AM keystores.
4. Deploy Apache Tomcat 10 with PingAM (configured for 512MB heap).
5. Poll AM health until `/am/isAlive.jsp` returns HTTP 200.
6. Execute Amster using File-Based Configuration (FBC) to link AM with Server 1's DS.
7. Deploy PingGateway (IG 512MB heap) with auto-generated TLS keys (alias: `ssl-key-pair`).
8. Apply REST configuration (creating OAuth2 clients, journeys, and services).
9. Deploy Platform UI (Admin, Login, and EndUser webapps into Tomcat).
10. Provision test users into the identity tier.

#### 8. Verify Server 2
```bash
./misc/platform8-control.sh status
```

---

## 7. Step-by-Step Installation: Single-Server All-in-One

For single-server installations (16 GB+ RAM host):

```bash
# 1. Switch to install user
sudo su - fradmin
cd ~/Platform8Install

# 2. Place all 6 software binaries into software/ subdirectories

# 3. Ensure platformconfig.env has default 127.0.0.1 IPs:
SERVER1_IP="127.0.0.1"
SERVER2_IP="127.0.0.1"

# 4. Run prerequisites setup
./misc/platform8-setup.sh

# 5. Launch full installer
./install_platform8.sh
```
When prompted:
- **Topology:** Select `1` (Full Single-Server Install).
- **Configuration Mode:** Select `1` (File Based Config - FBC [Recommended]).

---

## 8. Post-Installation Access & Verification

### Browser Access via Gateway (Recommended)

All client traffic is routed securely through PingGateway:

| Application | Gateway URL | Direct Port (Internal) |
|-------------|-------------|------------------------|
| **Platform Gateway Entrypoint** | `https://platform.example.com:9443` | Port 9443 |
| **Platform Login Page** | `https://platform.example.com:9443/login/` | Port 8083 |
| **Admin Console** | `https://platform.example.com:9443/admin/` | Port 8082 |
| **End-User Self Service** | `https://platform.example.com:9443/enduser/` | Port 8888 |
| **AM Administration Console** | `http://am.example.com:8081/am` | Port 8081 |
| **IDM Administration Console** | `http://openidm.example.com:8080/admin` | Port 8080 |

### Administrative Credentials
- **AM Administrator:**
  - Username: `amadmin`
  - Password: `${DEFAULT_PASSWORD}` (default: `password`)
- **IDM Administrator:**
  - Username: `openidm-admin`
  - Password: `${DEFAULT_PASSWORD}` (default: `password`)
- **Directory Manager:**
  - Bind DN: `cn=Directory Manager`
  - Password: `${DS_ADMIN_PASSWORD}` (default: `password`)

### Default Test Users
When test user creation is enabled (`INSTALL_TEST_USERS=true`), the installer creates 5 test accounts in the `alpha` realm:
- **Usernames:** `testuser1`, `testuser2`, `testuser3`, `testuser4`, `testuser5`
- **Password:** `!@34QWer` (or the value set in `${TEST_USER_PASSWORD}`)

---

## 9. Day-2 Operations & Service Control

### Managing All Services (`misc/platform8-control.sh`)

Use the central service management script to control components:

```bash
# Check status of all components
./misc/platform8-control.sh status

# Start all components (in proper dependency order)
./misc/platform8-control.sh start

# Stop all components
./misc/platform8-control.sh stop

# Restart all components
./misc/platform8-control.sh restart

# Backup all configurations
./misc/platform8-control.sh backup
```

### Managing Directory Server Instances (`misc/manage-ds.sh`)

Manage the Directory Server backends and instances:

```bash
# Check DS running status and process IDs
./misc/manage-ds.sh status

# Stop / Start / Restart Directory Server
./misc/manage-ds.sh stop
./misc/manage-ds.sh start
./misc/manage-ds.sh restart
```

### Adjusting Directory Disk Thresholds (`ds/configure_disk_thresholds.sh`)

If running on low disk space (e.g. cloud VMs with < 10GB free space), DS enters a read-only lock mode. Run:
```bash
./ds/configure_disk_thresholds.sh
```
This adjusts low-disk thresholds to 2 GB and full-disk thresholds to 1 GB.

---

## 10. Troubleshooting & Common Errors

### 1. Error: `PKIX path building failed` in Amster / AM cannot connect to DS
- **Symptom:** During AM deployment on Server 2, Amster fails with `unable to find valid certification path to requested target` while connecting to `ldaps://ds1.example.com:1636`.
- **Root Cause:** Server 2 does not have the Directory Server CA certificate imported into its Java truststore.
- **Fix:**
  1. On Server 1, copy `misc/keys/ds-ca-cert.pem` to Server 2:
     ```bash
     scp /ping/am/truststore/ds-ca-cert.pem fradmin@<server2-ip>:~/Platform8Install/misc/keys/
     ```
  2. On Server 2, re-import into the JVM truststore:
     ```bash
     sudo keytool -importcert -noprompt \
       -alias ping-ds-ca \
       -keystore "${JAVA_HOME}/lib/security/cacerts" \
       -storepass changeit \
       -file ~/Platform8Install/misc/keys/ds-ca-cert.pem
     ```
  3. Rerun `./install_server2.sh`.

---

### 2. Error: `dskeymgr: command not found` during IG setup on Server 2
- **Symptom:** `ig8.sh` fails with an error trying to run `/ping/ds/opendj/bin/dskeymgr`.
- **Root Cause:** In earlier versions, `ig8.sh` assumed Directory Services was installed on the same host. On Server 2, DS does not exist.
- **Fix:** The repository now detects if `dskeymgr` is missing and automatically falls back to standard Java `keytool` using alias `ssl-key-pair` to generate the PKCS12 keystore. If updating an older clone, pull the latest scripts from this repository.

---

### 3. Error: `Connection refused` on port 1636 from Server 2
- **Symptom:** Server 2 cannot connect to `ds1.example.com:1636`.
- **Checks:**
  1. Verify DS is running on Server 1:
     ```bash
     ./misc/manage-ds.sh status
     ```
  2. Check firewall on Server 1:
     ```bash
     sudo firewall-cmd --permanent --add-port=1636/tcp && sudo firewall-cmd --reload
     ```
  3. Verify `/etc/hosts` on Server 2 maps `ds1.example.com` to Server 1's actual IP address, **NOT** `127.0.0.1`.

---

### 4. Error: AM deployment times out or returns HTTP 404/503
- **Symptom:** Amster fails to connect to AM because Tomcat is still unpacking `am.war`.
- **Fix:** The updated scripts now incorporate an automated health check loop (`wait_for_am_ready()`) that polls `http://am.example.com:8081/am/isAlive.jsp` until it responds with HTTP 200. Inspect Tomcat output if stuck:
  ```bash
  tail -f /opt/tomcat/logs/catalina.out
  ```

---

### 5. Error: `jq: command not found` or token parsing error
- **Symptom:** REST configuration fails while extracting the `ADMIN_TOKEN`.
- **Fix:** The configuration scripts have been updated with a fallback parser (`python3` -> `jq` -> `grep/cut`). To ensure all features work optimally, install `jq` and `python3`:
  ```bash
  sudo dnf install -y jq python3   # CentOS / RHEL
  sudo apt-get install -y jq python3 # Ubuntu / Debian
  ```

---

### 6. Component Log Files Reference

When debugging, consult the logs in these locations:

| Component | Log File Location |
|-----------|-------------------|
| **Access Management (AM)** | `/opt/tomcat/logs/catalina.out`<br>`/ping/am/am/var/debug/` |
| **Directory Services (DS)** | `/ping/ds/opendj/logs/errors`<br>`/ping/ds/opendj/logs/access` |
| **Identity Management (IDM)** | `/ping/openidm/logs/openidm0.log` |
| **PingGateway (IG)** | `/ping/identity-gateway/logs/` |
| **Amster CLI** | `/ping/software/am/amster/logs/` |
| **Platform UI** | `/opt/tomcat/logs/catalina.out` |

---

## 11. Component Directory Reference

Default directory structure created under `/ping` and `/opt`:

```
/ping/
├── ds/
│   └── opendj/                 # Consolidated Directory Server instance
│       ├── bin/                # dsconfig, start-ds, stop-ds, status
│       ├── config/             # config.ldif
│       └── logs/               # access, errors
├── openidm/                    # Identity Management instance
│   ├── bin/                    # start, shutdown
│   ├── conf/                   # JSON configuration files
│   └── logs/                   # openidm.log
├── identity-gateway/           # PingGateway instance
│   ├── bin/                    # start, stop
│   ├── config/                 # admin.json, config.json, routes/
│   └── security/               # keystore.pkcs12
└── am/
    └── truststore/             # ds-ca-cert.pem, keystore.jks

/opt/
└── tomcat/                     # Apache Tomcat 10
    ├── bin/                    # startup.sh, shutdown.sh
    ├── conf/                   # server.xml, context.xml
    ├── logs/                   # catalina.out
    └── webapps/
        ├── am.war & am/        # Access Management application
        ├── admin/              # Platform Admin UI
        ├── login/              # Platform Login UI
        └── enduser/            # Platform End-User UI
```

---

## 12. License & Support

This installation suite is provided for development, evaluation, and proof-of-concept deployments of Ping Identity Platform 8. For production deployments, consult Ping Identity documentation for high availability clustering, certificate authority integration, and OS-level security hardening.
