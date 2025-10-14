# **VaultWarden OCI Minimal** 

A robust, self-hosted VaultWarden stack designed for small teams (10 or fewer users). This project is engineered to be a "set and forget" system with automated setup, monitoring, backups, and maintenance, all while avoiding over-engineering.

This enhanced version is **fully dynamic and portable**. Project names, container names, and paths are generated automatically based on the root folder name, allowing you to rename or move the project without breaking any scripts.

## **🚀 Quick Start**

**⚠️ IMPORTANT: Always use the provided scripts to manage the stack. Never run docker compose up directly.**

Bash

\# 1\. Clone the repository  
git clone \<your-repository-url\>  
cd \<project-folder-name\>

\# 2\. Run the initial setup script (as root)  
\# This will install dependencies, configure security, and create your settings file.  
sudo ./tools/init-setup.sh

\# 3\. Start the stack  
\# This script loads configuration and starts the containers in the correct order.  
./startup.sh

\# 4\. Check the status  
docker compose ps

---

## **✨ Key Features**

* **Fully Dynamic & Portable**: Rename the project folder, and all scripts, service names, and container configurations will adapt automatically. No hardcoded paths or names.  
* **Automated Initial Setup**: The init-setup.sh script handles everything from installing Docker and Fail2ban to configuring the firewall and generating initial secrets.  
* **Robust Startup Contract**: startup.sh is the mandatory entrypoint that securely loads configurations, prepares the environment, and performs pre-flight checks before launching containers.  
* **Automated Monitoring & Self-Healing**: A cron-scheduled script (tools/monitor.sh) continuously checks the health of the stack. It will attempt to automatically restart failed services before sending an alert.  
* **Comprehensive Backup & Restore**:  
  * Automated daily database backups and weekly full-system backups.  
  * Backups are compressed, encrypted, and support multiple formats (binary, SQL, JSON, CSV) for maximum flexibility.  
  * An interactive restore script (tools/restore.sh) simplifies recovery on a new or existing host.  
* **Security First**:  
  * Integrated Fail2ban with Cloudflare support to block malicious IPs at the edge.  
  * Secure secrets management with support for local settings.json and OCI Vault, ensuring secrets are loaded into memory at runtime and never written to disk.  
  * Hardened Caddy configuration with modern security headers.  
* **Automated Maintenance**: Includes scripts for SQLite database optimization (tools/sqlite-maintenance.sh) and keeping Cloudflare's IP lists up to date (tools/update-cloudflare-ips.sh), all managed via cron.

---

## **📁 Project Structure**

This project uses a modular library system to ensure code is consistent, reusable, and easy to maintain.

* ./lib/: The core of the project's logic.  
  * config.sh: Handles all dynamic configuration, path detection, and secret loading. This is the single source of truth for project-level variables.  
  * system.sh: Provides system-level utilities for package management, service control, and file operations.  
  * validation.sh: Contains functions for prerequisite checks (Docker, OS, resources).  
  * logging.sh: A centralized library for consistent, color-coded logging.  
  * monitoring.sh: Core functions for health checks and self-healing.  
  * backup-core.sh, backup-formats.sh, restore-lib.sh: The complete, robust backup and restore toolkit.  
* ./tools/: All user-facing scripts for setup, maintenance, and operations.  
* ./caddy/: Caddy webserver configuration.  
* ./fail2ban/: Fail2ban filters and actions.  
* ./templates/: Configuration templates used by the scripts.

---

## **⚙️ How Dynamic Configuration Works**

The entire stack's identity is derived from its root folder name.

1. **Project Name**: When any script is run, lib/config.sh determines the PROJECT\_NAME from the base name of the root directory (e.g., VaultWarden-OCI-Minimal becomes vaultwarden-oci-minimal).  
2. **Service & Container Names**: This PROJECT\_NAME is then used to dynamically name the systemd service (vaultwarden-oci-minimal.service), Docker Compose project, and network bridge.  
3. **Paths**: The primary data directory (PROJECT\_STATE\_DIR) is also derived from this name (e.g., /var/lib/vaultwarden-oci-minimal).

This means you can clone the repository into a directory named my-private-vault, and everything will automatically be configured to use my-private-vault as its identifier.

---

## **troubleshooting**

### **Enable Debug Mode**

To get more verbose output from any script, set the DEBUG environment variable:

Bash

\# Example for startup script  
export DEBUG=1  
./startup.sh

\# Example for initial setup  
sudo DEBUG=1 ./tools/init-setup.sh

### **Common Issues**

* **"Docker not found" or "jq not found"**:  
  * **Solution**: You must run the initial setup script first. It will install all required dependencies.  
    Bash  
    sudo ./tools/init-setup.sh

* **"settings.json not found"**:  
  * **Solution**: This file is generated during the initial setup. Run the setup script to create it.  
* **Services Fail to Start**:  
  * **Solution**: Check the Docker logs for specific error messages.  
    Bash  
    \# View logs for all containers  
    docker compose logs

    \# Follow logs for a specific container (e.g., vaultwarden)  
    docker compose logs \-f vaultwarden  
