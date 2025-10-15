# VaultWarden OCI Minimal

**A production-ready, self-hosted VaultWarden stack designed for small teams (≤10 users)**

[![Deploy Status](https://img.shields.io/badge/Deploy%20Ready-Production-brightgreen)](docs/QuickStart.md)
[![Architecture](https://img.shields.io/badge/Architecture-Modular-blue)](docs/Architecture.md)
[![Security](https://img.shields.io/badge/Security-Hardened-red)](docs/Security.md)
[![OCI Compatible](https://img.shields.io/badge/OCI-A1%20Flex%20Ready-orange)](docs/Deployment.md)

> **🎯 Project Goal**: "Set and forget" VaultWarden deployment with enterprise-grade automation, monitoring, and security—without the complexity.

## 🚨 **Critical Setup Order**

**⚠️ NEVER run `docker compose up` directly. Always use the provided scripts.**

```bash
# 1. Make scripts executable (required after git clone)
chmod +x startup.sh tools/*.sh

# 2. Run setup FIRST (handles all dependencies)
sudo ./tools/init-setup.sh

# 3. Start services (handles configuration and health checks)
./startup.sh
```

## ✨ **Why This Project Exists**

Most VaultWarden deployments require manual configuration of Docker, reverse proxies, SSL certificates, backups, monitoring, and security. This project **automates everything**:

- **Zero Manual Configuration**: One command installs Docker, configures security, generates secrets, and sets up monitoring
- **Dynamic & Portable**: No hardcoded paths—rename the project folder and everything adapts automatically
- **Production Security**: UFW firewall, fail2ban with CloudFlare integration, secure file permissions, automated updates
- **Comprehensive Monitoring**: Health checks every 5 minutes with automatic recovery and email alerts
- **Automated Backups**: Daily database backups, weekly full system backups with encryption and retention management
- **CloudFlare Ready**: Built-in CloudFlare proxy support with automatic IP whitelist updates

## 🏗️ **Architecture Overview**

### **Dynamic Project System**
Everything adapts based on your project folder name:
```bash
# Clone to ANY name
git clone repo.git my-company-vault
cd my-company-vault

# Everything auto-configures:
# - Project: my-company-vault
# - Data: /var/lib/my-company-vault
# - Service: my-company-vault.service
# - Network: my-company-vault_network
# - Containers: my-company-vault_vaultwarden, etc.
```

### **Service Stack**
- **VaultWarden**: Password manager (ARM/x64 compatible, 512MB limit)
- **Caddy**: Reverse proxy with automatic SSL (Let's Encrypt)
- **Fail2ban**: Intrusion prevention with CloudFlare integration
- **Watchtower**: Automated container updates (configurable schedule)
- **DDClient**: Dynamic DNS updates (optional, for changing IPs)

### **Library System (`./lib/`)**
Modular, reusable bash libraries:
- **`config.sh`**: Dynamic configuration loading (local files or OCI Vault)
- **`validation.sh`**: System requirements and health validation
- **`system.sh`**: Package management and service control
- **`logging.sh`**: Consistent, color-coded logging
- **`monitoring.sh`**: Health checks and self-healing
- **`backup-*.sh`**: Comprehensive backup/restore system

## 📋 **Requirements**

### **Minimum System**
- **OS**: Ubuntu 24.04 LTS (minimal install supported)
- **CPU**: 1 vCPU (ARM64/x86_64)
- **RAM**: 2GB (recommended for 10 users)
- **Storage**: 20GB available
- **Network**: Public IP, ports 80/443 accessible

### **Recommended (OCI A1 Flex)**
- **Shape**: VM.Standard.A1.Flex
- **CPU**: 2 OCPUs
- **RAM**: 12GB
- **Storage**: 50GB boot volume

## 🚀 **Quick Deployment**

### **Standard Installation (30 minutes)**
```bash
# 1. Connect to your server
ssh ubuntu@your-server-ip
sudo su -

# 2. Clone repository
cd /opt
git clone https://github.com/killer23d/VaultWarden-OCI-Minimal.git
cd VaultWarden-OCI-Minimal

# 3. Make executable and setup
chmod +x startup.sh tools/*.sh
sudo ./tools/init-setup.sh

# 4. Start services
./startup.sh

# 5. Access VaultWarden
# Web: https://your-domain.com
# Admin: https://your-domain.com/admin
# Admin Token: Get from settings.json
```

### **Automated Installation**
```bash
# Non-interactive setup for scripts/automation
sudo ./tools/init-setup.sh --auto
```

## ⚙️ **Configuration Management**

### **Local Configuration**
Settings stored in `settings.json` (created during setup):
```json
{
  "DOMAIN": "https://vault.example.com",
  "ADMIN_EMAIL": "admin@example.com",
  "ADMIN_TOKEN": "generated-secure-token",
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_FROM": "vaultwarden@example.com",
  "CLOUDFLARE_EMAIL": "your-cf-email@example.com",
  "CLOUDFLARE_API_KEY": "your-global-api-key"
}
```

### **OCI Vault Integration**
Enterprise secret management:
```bash
# Setup OCI Vault (optional)
./tools/oci-setup.sh

# Automatic fallback to local files if OCI unavailable
```

## 🛡️ **Security Features**

### **Automated Security Hardening**
- **UFW Firewall**: Configured during setup (SSH, HTTP, HTTPS only)
- **Fail2ban**: Multi-layer protection with CloudFlare edge blocking
- **File Permissions**: Sensitive files automatically secured (600 permissions)
- **Container Security**: Non-root execution where possible, resource limits

### **CloudFlare Integration**
- **Edge Protection**: DDoS mitigation and geographic filtering
- **IP Whitelisting**: Automatic CloudFlare IP range updates
- **Fail2ban Actions**: Blocked IPs added to CloudFlare firewall rules

### **SSL/TLS**
- **Automatic Certificates**: Let's Encrypt via Caddy
- **Security Headers**: HSTS, CSP, X-Frame-Options configured
- **Perfect Forward Secrecy**: Modern cipher suites only

## 📊 **Monitoring & Automation**

### **Automated Health Monitoring**
```bash
# Health checks every 5 minutes (via cron)
# - Container health and resource usage
# - Database integrity and performance
# - SSL certificate expiration
# - Disk space and log rotation
# - Network connectivity
```

### **Automated Maintenance**
```bash
# Daily (1 AM): Database backups
# Weekly (Sunday 12 AM): Full system backups
# Daily (3 AM): CloudFlare IP updates
# Daily (4 AM): Log rotation and cleanup
# Weekly (Monday 2 AM): Full database optimization
```

### **Self-Healing**
- **Service Recovery**: Automatic restart of failed containers
- **Resource Management**: Log rotation prevents disk exhaustion
- **Update Management**: Automated security updates (configurable)
- **Alert Escalation**: Email notifications for manual intervention required

## 💾 **Backup & Restore**

### **Automated Backups**
- **Database**: Daily SQLite backups with integrity checks
- **System**: Weekly full configuration and data backups
- **Formats**: Binary, SQL, JSON, CSV exports
- **Encryption**: AES-256 encryption with configurable passphrases
- **Retention**: Configurable cleanup (default: 30 days)

### **Backup Management**
```bash
# Manual backup
./tools/create-full-backup.sh

# Database only backup
./tools/db-backup.sh

# Interactive restore
./tools/restore.sh

# List available backups
./tools/restore.sh --list
```

## 🔧 **Operations**

### **Daily Operations**
```bash
# Check system status
./tools/monitor.sh --summary

# View service status
docker compose ps

# View logs
docker compose logs -f

# Restart services
./startup.sh
```

### **Maintenance Commands**
```bash
# Database maintenance
./tools/sqlite-maintenance.sh --full

# Update CloudFlare IPs
./tools/update-cloudflare-ips.sh

# Health check with details
./tools/monitor.sh --verbose

# Configuration validation
./startup.sh --validate
```

## 🆘 **Troubleshooting**

### **Common Issues**

#### **"Cannot access web interface"**
```bash
# Check container status
docker compose ps

# Check firewall
sudo ufw status

# Check DNS resolution
nslookup your-domain.com

# Check domain in config
grep DOMAIN settings.json
```

#### **"SSL certificate issues"**
```bash
# Check certificate status
docker compose logs caddy | grep -i certificate

# Force certificate refresh
docker compose exec caddy caddy reload

# Verify domain is publicly accessible (required for Let's Encrypt)
```

#### **"Admin panel access denied"**
```bash
# Get admin token
sudo jq -r '.ADMIN_TOKEN' settings.json

# If empty, regenerate
openssl rand -base64 32

# Update config and restart
./startup.sh
```

### **Debug Mode**
```bash
# Enable debug logging for any script
export DEBUG=1
./startup.sh

# Check detailed logs
docker compose logs --tail=100
```

## 📚 **Documentation**

Comprehensive documentation in [`./docs/`](docs/):

- **[Quick Start](docs/QuickStart.md)**: 30-minute deployment guide
- **[Architecture](docs/Architecture.md)**: System design and components
- **[Security](docs/Security.md)**: Security features and hardening
- **[Monitoring](docs/Monitoring.md)**: Health checks and alerting
- **[Backup & Restore](docs/BackupRestore.md)**: Data protection procedures
- **[CloudFlare Setup](docs/Cloudflare.md)**: Enhanced protection configuration
- **[OCI Vault](docs/OCI-Vault.md)**: Enterprise secret management
- **[Troubleshooting](docs/Troubleshooting.md)**: Common issues and solutions
- **[Operations Runbook](docs/OperationsRunbook.md)**: Day-to-day operations
- **[Script Reference](docs/ScriptReference.md)**: Complete script documentation

## 🤝 **Contributing**

### **Development Setup**
```bash
# Fork repository and clone
git clone https://github.com/yourusername/VaultWarden-OCI-Minimal.git
cd VaultWarden-OCI-Minimal

# Enable debug mode
export DEBUG=1

# Test configuration system
source lib/config.sh && _load_configuration

# Validate scripts
shellcheck tools/*.sh lib/*.sh
```

### **Testing**
```bash
# Test backup/restore
./tools/create-full-backup.sh --test
./tools/restore.sh --dry-run

# Test monitoring
./tools/monitor.sh --test-all

# Validate complete setup
./startup.sh --validate
```

## 🔗 **Project Links**

- **Repository**: [GitHub](https://github.com/killer23d/VaultWarden-OCI-Minimal)
- **Issues**: [Bug Reports](https://github.com/killer23d/VaultWarden-OCI-Minimal/issues)
- **Discussions**: [Q&A and Features](https://github.com/killer23d/VaultWarden-OCI-Minimal/discussions)
- **Security**: [Security Policy](SECURITY.md)

## 📄 **License**

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🎯 **Success Metrics**

- **Deployment Time**: < 30 minutes from zero to production
- **Uptime Target**: > 99.5% (with proper monitoring)
- **Security Score**: A+ SSL Labs rating
- **Maintenance**: < 5 minutes/month human intervention required
- **Recovery Time**: < 10 minutes from backup (automated)

**💡 Remember**: This is designed as a "set and forget" solution. After initial setup, automated systems handle maintenance, monitoring, security updates, and backups with minimal human intervention."""
