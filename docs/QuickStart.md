# Quick Start Guide

## Overview

This guide gets you from zero to a fully operational VaultWarden instance in under 30 minutes. VaultWarden-OCI-Minimal is designed for rapid deployment with automated setup and configuration.

## Prerequisites Checklist

### Server Requirements
- [ ] **Ubuntu 24.04 LTS** (minimal installation supported)
- [ ] **2GB RAM minimum** (4GB recommended for 10 users)
- [ ] **20GB storage minimum** (50GB recommended)
- [ ] **Internet connectivity** for setup and updates
- [ ] **Root or sudo access**

### Network Requirements
- [ ] **Domain name** registered and configured
- [ ] **DNS pointing** to your server IP address
- [ ] **Ports 22, 80, 443** accessible from internet
- [ ] **Cloudflare account** (optional but recommended)

### Access Information
- [ ] **Server IP address**
- [ ] **SSH private key** or password
- [ ] **Domain name** you'll use (e.g., vault.example.com)
- [ ] **Email address** for admin notifications

## 30-Minute Deployment

### Step 1: Server Access (2 minutes)

#### Connect to Your Server
```bash
# SSH to your server
ssh -i your-key.pem ubuntu@YOUR_SERVER_IP

# Switch to root (or use sudo for all commands)
sudo su -

# Update system (recommended)
apt update && apt upgrade -y
```

#### Verify System Requirements
```bash
# Check OS version
cat /etc/os-release

# Check available memory
free -h

# Check disk space
df -h

# Check internet connectivity
ping -c 3 google.com
```

### Step 2: Download and Setup (5 minutes)

#### Clone Repository
```bash
# Navigate to installation directory
cd /opt

# Clone the repository
git clone https://github.com/killer23d/VaultWarden-OCI-Minimal.git

# Enter project directory
cd VaultWarden-OCI-Minimal

# Make scripts executable
chmod +x startup.sh tools/*.sh

# Verify files
ls -la tools/
```

### Step 3: Automated Installation (15 minutes)

#### Run Complete Setup
```bash
# Run the comprehensive setup script
sudo ./tools/init-setup.sh

# This script will:
# ✅ Install Docker and required packages
# ✅ Configure firewall and security (UFW, fail2ban)
# ✅ Generate secure configuration with random tokens
# ✅ Set up automated maintenance and monitoring
# ✅ Create all required directories and permissions
# ✅ Install cron jobs for backups and maintenance
```

#### Interactive Configuration
During setup, provide the following information:
```bash
# Required Information
Domain name: https://vault.example.com
Admin email: admin@example.com
SMTP host: smtp.gmail.com
SMTP from address: noreply@example.com

# Optional Information (can be configured later)
SMTP username: (leave blank if unsure)
SMTP password: (leave blank if unsure)
Cloudflare email: (for enhanced security)
Cloudflare API key: (for fail2ban integration)
```

#### Automated Mode (For Scripts)
```bash
# Non-interactive setup with defaults
sudo ./tools/init-setup.sh --auto
```

### Step 4: Start Services (3 minutes)

#### Launch VaultWarden
```bash
# Start all services using the startup script
./startup.sh

# Expected output:
# ✅ Configuration loaded successfully
# ✅ Environment prepared
# ✅ Services started successfully
# ✅ VaultWarden is healthy
# ✅ Service information displayed
```

#### Verify Deployment
```bash
# Check container status
docker compose ps

# Expected output shows all containers as "Up" and "healthy"
# - vaultwarden: Up (healthy)
# - caddy: Up (healthy)
# - fail2ban: Up
# - watchtower: Up

# Test web interface
curl -I https://vault.example.com
# Should return "HTTP/2 200" or "HTTP/1.1 200"
```

### Step 5: Initial Configuration (5 minutes)

#### Access Admin Panel
1. **Open browser**: Navigate to `https://vault.example.com/admin`
2. **Admin token**: Use token from `/opt/VaultWarden-OCI-Minimal/settings.json`
   ```bash
   # Get admin token
   sudo jq -r '.ADMIN_TOKEN' /opt/VaultWarden-OCI-Minimal/settings.json
   ```
3. **Configure settings**:
   - Disable user registration (if desired)
   - Configure organization settings
   - Set up SMTP if not done during installation

#### Create First User Account
1. **Access main interface**: Navigate to `https://vault.example.com`
2. **Create account**: 
   - Either enable signup temporarily in admin panel
   - Or create user directly in admin panel
3. **Test functionality**:
   - Log in to new account
   - Create a test vault item
   - Verify synchronization works

## Post-Deployment Verification

### System Health Check

#### Automated Health Verification
```bash
# Comprehensive system validation
./startup.sh --validate

# Monitor system health
./tools/monitor.sh --summary

# Expected output:
# ✅ All containers healthy
# ✅ Database accessible
# ✅ SSL certificate valid
# ✅ Backup system operational
```

#### Manual Verification Steps
```bash
# 1. Web interface accessibility
curl -I https://vault.example.com
# Should return HTTP 200

# 2. SSL certificate verification
openssl s_client -connect vault.example.com:443 -servername vault.example.com < /dev/null 2>/dev/null | openssl x509 -noout -text | grep -A 2 "Validity"

# 3. Database functionality
./tools/sqlite-maintenance.sh --check
# Should report "Database integrity: OK"

# 4. Backup system test
./tools/db-backup.sh --dry-run
# Should complete without errors

# 5. Monitoring system test
./tools/monitor.sh --test-all
# Should pass all tests
```

### Security Verification

#### Firewall Configuration
```bash
# Check UFW status
sudo ufw status verbose

# Expected rules:
# 22/tcp ALLOW IN
# 80/tcp ALLOW IN
# 443/tcp ALLOW IN
# Default: deny (incoming), allow (outgoing)
```

#### Fail2ban Status
```bash
# Check fail2ban jails
sudo fail2ban-client status

# Expected jails:
# - sshd (SSH protection)
# - vaultwarden (Application protection)
# - caddy (Proxy protection)
```

#### File Permissions
```bash
# Verify secure permissions
ls -la /opt/VaultWarden-OCI-Minimal/settings.json
# Should show: -rw------- 1 root root (600 permissions)

ls -ld /var/lib/*/backups
# Should show: drwx------ (700 permissions)
```

## Quick Configuration

### Essential Settings

#### Configure Email Notifications
Edit `/opt/VaultWarden-OCI-Minimal/settings.json`:
```json
{
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_PORT": 587,
  "SMTP_SECURITY": "starttls",
  "SMTP_USERNAME": "your-email@gmail.com",
  "SMTP_PASSWORD": "your-app-password",
  "SMTP_FROM": "vaultwarden@yourdomain.com",
  "ADMIN_EMAIL": "admin@yourdomain.com"
}
```

Then restart: `./startup.sh`

#### Configure User Registration
```json
{
  "SIGNUPS_ALLOWED": false,
  "INVITATIONS_ALLOWED": true,
  "INVITATION_EXPIRATION_HOURS": 120
}
```

#### Enable Push Notifications (Optional)
```json
{
  "PUSH_ENABLED": true,
  "PUSH_INSTALLATION_ID": "your-installation-id",
  "PUSH_INSTALLATION_KEY": "your-installation-key"
}
```

### Performance Tuning

#### For Larger Teams (5-10 users)
Edit `docker-compose.yml` resource limits:
```yaml
services:
  vaultwarden:
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '2.0'
        reservations:
          memory: 512M
          cpus: '1.0'
```

#### Database Optimization
```bash
# Run database optimization
./tools/sqlite-maintenance.sh --full

# Schedule regular maintenance (already automated)
crontab -l | grep sqlite-maintenance
```

## Common Quick Start Issues

### Issue 1: Cannot Access Web Interface

#### Symptoms
- Browser shows "connection refused" or "site can't be reached"
- `curl -I https://vault.example.com` fails

#### Quick Fix
```bash
# 1. Check container status
docker compose ps
# If containers are down:
./startup.sh

# 2. Check firewall
sudo ufw status
# If ports 80/443 are not allowed:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 3. Check DNS
nslookup vault.example.com
# If DNS is not resolving, update your DNS settings

# 4. Check domain configuration
grep DOMAIN /opt/VaultWarden-OCI-Minimal/settings.json
# Should match your actual domain
```

### Issue 2: SSL Certificate Problems

#### Symptoms
- Browser shows SSL warnings
- Certificate appears invalid or self-signed

#### Quick Fix
```bash
# 1. Wait for certificate generation (can take 5-10 minutes)
docker compose logs caddy | grep -i certificate

# 2. Check Caddy configuration
docker compose exec caddy caddy list-certificates

# 3. Force certificate renewal
docker compose exec caddy caddy reload

# 4. Verify domain accessibility from internet
# (Caddy needs to validate domain ownership)
```

### Issue 3: Admin Panel Access Issues

#### Symptoms
- "Invalid admin token" message
- Cannot access `/admin` endpoint

#### Quick Fix
```bash
# 1. Get correct admin token
sudo jq -r '.ADMIN_TOKEN' /opt/VaultWarden-OCI-Minimal/settings.json

# 2. Verify admin token is not empty
# If empty, regenerate:
openssl rand -base64 32

# 3. Update settings.json with new token
sudo nano /opt/VaultWarden-OCI-Minimal/settings.json

# 4. Restart services
./startup.sh
```

### Issue 4: Email/SMTP Not Working

#### Symptoms
- No email notifications received
- SMTP errors in logs

#### Quick Fix
```bash
# 1. Test SMTP connectivity
telnet smtp.gmail.com 587

# 2. Check SMTP configuration
grep SMTP /opt/VaultWarden-OCI-Minimal/settings.json

# 3. For Gmail, use App Password instead of regular password
# Generate at: https://myaccount.google.com/apppasswords

# 4. Test email functionality
./tools/monitor.sh --test-email
```

## Next Steps After Quick Start

### Immediate Actions (First Hour)
1. **Backup Admin Token**: Save admin token securely
2. **Create User Accounts**: Set up accounts for your team
3. **Test Functionality**: Create vaults, add passwords, test sync
4. **Configure Mobile Apps**: Install Bitwarden apps and test

### Within First Day
1. **Setup Off-site Backups**: Configure cloud storage for backups
2. **Configure Cloudflare**: Set up enhanced security and performance
3. **Review Security Settings**: Audit admin panel configuration
4. **Test Backup/Restore**: Verify backup system works correctly

### Within First Week
1. **Monitor System Health**: Review automated monitoring reports
2. **Performance Tuning**: Adjust settings based on actual usage
3. **User Training**: Train team on VaultWarden features
4. **Documentation**: Document your specific configuration choices

## Support and Resources

### Built-in Help
```bash
# Get help for any script
./startup.sh --help
./tools/init-setup.sh --help
./tools/monitor.sh --help

# View configuration paths
source lib/config.sh && _get_project_paths

# Check system status anytime
./tools/monitor.sh --summary
```

### Log Locations
```bash
# Application logs
/var/lib/*/logs/vaultwarden/
/var/lib/*/logs/caddy/
/var/lib/*/logs/fail2ban/

# System logs
journalctl -t monitor
journalctl -t sqlite-maintenance
journalctl -t backup
```

### Troubleshooting Resources
- **Troubleshooting Guide**: `docs/Troubleshooting.md`
- **Security Guide**: `docs/Security.md`
- **Monitoring Guide**: `docs/Monitoring.md`
- **Architecture Guide**: `docs/Architecture.md`

This quick start guide provides a streamlined path to a fully operational, production-ready VaultWarden deployment with comprehensive automation and monitoring.
