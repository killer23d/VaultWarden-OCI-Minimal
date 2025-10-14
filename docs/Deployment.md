# Deployment Guide

## Pre-Deployment Planning

### Infrastructure Requirements

#### Oracle Cloud Infrastructure (OCI) A1 Flex - Recommended
```
Shape: VM.Standard.A1.Flex
- OCPUs: 2 (minimum: 1)
- Memory: 12GB (minimum: 2GB)
- Boot Volume: 50GB (minimum: 20GB)
- Network: Public IP with Internet Gateway
- OS: Ubuntu 24.04 LTS Minimal
```

#### Alternative Cloud Providers
- **AWS**: t4g.small or larger (ARM64) / t3.small (x86_64)
- **Google Cloud**: e2-small or larger
- **Azure**: B1s or larger
- **DigitalOcean**: Basic Droplet 2GB RAM or larger

#### Network Requirements
- **Internet Access**: Required for initial setup and updates
- **Ports**: 22 (SSH), 80 (HTTP redirect), 443 (HTTPS)
- **DNS**: Domain name pointing to server IP
- **Cloudflare**: Recommended for DDoS protection and CDN

### Domain and DNS Setup

#### Domain Requirements
1. **Domain Registration**: Any domain registrar
2. **DNS Management**: Point to Cloudflare (recommended)
3. **Subdomain**: Use subdomain for VaultWarden (e.g., vault.example.com)

#### Cloudflare Configuration
```bash
# DNS Records (in Cloudflare dashboard)
Type: A
Name: vault (or your chosen subdomain)
Content: YOUR_SERVER_IP
Proxy Status: Proxied (orange cloud)
TTL: Auto

# SSL/TLS Settings
SSL/TLS Mode: Full (strict)
Always Use HTTPS: On
Minimum TLS Version: 1.2
```

### Pre-Installation Checklist

- [ ] Server provisioned with Ubuntu 24.04 LTS
- [ ] SSH access configured with key-based authentication
- [ ] Domain DNS pointing to server IP
- [ ] Cloudflare proxy enabled (if using Cloudflare)
- [ ] Root or sudo access available
- [ ] Server updated with latest packages

## Installation Process

### Step 1: Server Preparation

#### Connect to Server
```bash
# SSH to your server
ssh -i your-key.pem ubuntu@YOUR_SERVER_IP

# Switch to root (or use sudo for all commands)
sudo su -
```

#### System Update
```bash
# Update package lists and system
apt update && apt upgrade -y

# Install basic utilities (optional)
apt install -y htop curl wget git nano
```

### Step 2: Download and Setup

#### Clone Repository
```bash
# Navigate to desired location
cd /opt

# Clone the repository
git clone https://github.com/killer23d/VaultWarden-OCI-Minimal.git

# Enter project directory
cd VaultWarden-OCI-Minimal

# Make scripts executable
chmod +x startup.sh tools/*.sh
```

#### Alternative: Direct Download
```bash
# If git is not available
wget https://github.com/killer23d/VaultWarden-OCI-Minimal/archive/refs/heads/main.zip
unzip main.zip
mv VaultWarden-OCI-Minimal-main VaultWarden-OCI-Minimal
cd VaultWarden-OCI-Minimal
chmod +x startup.sh tools/*.sh
```

### Step 3: Initial Setup

#### Run Setup Script
```bash
# Run the comprehensive setup script
sudo ./tools/init-setup.sh
```

#### Setup Process Breakdown
The init-setup script will:
1. **Validate System**: Check OS, resources, and prerequisites
2. **Install Packages**: Docker, fail2ban, UFW, and utilities
3. **Configure Security**: Firewall rules and fail2ban settings
4. **Generate Configuration**: Create settings.json with secure defaults
5. **Setup Automation**: Install cron jobs for maintenance
6. **Create Directories**: All required data directories

#### Interactive Configuration
During setup, you'll be prompted for:
```bash
# Required Information
Domain: https://vault.example.com
Admin Email: admin@example.com
SMTP Host: smtp.gmail.com (or your SMTP server)
SMTP From: noreply@example.com
SMTP Username: (optional)
SMTP Password: (optional)

# Optional Cloudflare Integration
Cloudflare Email: your-cloudflare-email@example.com
Cloudflare API Key: your-global-api-key
```

#### Automated Setup (Non-Interactive)
```bash
# For scripted deployments
sudo ./tools/init-setup.sh --auto
```

### Step 4: Configuration Customization

#### Edit Configuration File
```bash
# Edit the generated configuration
nano settings.json
```

#### Key Configuration Options
```json
{
  "DOMAIN": "https://vault.example.com",
  "ADMIN_EMAIL": "admin@example.com",
  "ADMIN_TOKEN": "generated-secure-token",
  "SIGNUPS_ALLOWED": false,
  "WEBSOCKET_ENABLED": false,
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_PORT": 587,
  "SMTP_SECURITY": "starttls",
  "SMTP_FROM": "noreply@example.com",
  "SMTP_USERNAME": "your-username",
  "SMTP_PASSWORD": "your-password",
  "BACKUP_PASSPHRASE": "generated-backup-passphrase"
}
```

#### Optional: DDNS Configuration
```json
{
  "DDCLIENT_ENABLED": true,
  "DDCLIENT_PROTOCOL": "cloudflare",
  "DDCLIENT_LOGIN": "your-email@example.com",
  "DDCLIENT_PASSWORD": "your-cloudflare-token",
  "DDCLIENT_ZONE": "example.com",
  "DDCLIENT_HOST": "vault.example.com"
}
```

### Step 5: Start Services

#### Launch VaultWarden Stack
```bash
# Start all services
./startup.sh
```

#### Verify Deployment
```bash
# Check container status
docker compose ps

# View logs
docker compose logs -f

# Test web interface
curl -I https://vault.example.com
```

### Step 6: Initial Configuration

#### Access Admin Panel
1. **Open Browser**: Navigate to https://vault.example.com/admin
2. **Admin Token**: Use the token from settings.json
3. **Initial Setup**: Configure organization settings

#### Create First User
1. **Access Main Interface**: https://vault.example.com
2. **Registration**: Enable signups temporarily or create via admin panel
3. **Account Setup**: Create your first user account
4. **Disable Signups**: Set "SIGNUPS_ALLOWED": false in configuration

## Post-Deployment Configuration

### Security Hardening

#### SSH Security
```bash
# Edit SSH configuration
nano /etc/ssh/sshd_config

# Recommended settings
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3

# Restart SSH service
systemctl restart sshd
```

#### Firewall Verification
```bash
# Check UFW status
ufw status verbose

# Expected output should show:
# 22/tcp ALLOW IN
# 80/tcp ALLOW IN  
# 443/tcp ALLOW IN
# Default: deny (incoming), allow (outgoing)
```

#### Fail2ban Configuration
```bash
# Check fail2ban status
fail2ban-client status

# View VaultWarden jail status
fail2ban-client status vaultwarden
```

### Monitoring Setup

#### Verify Automated Monitoring
```bash
# Check cron jobs installation
crontab -l

# Should show monitoring, backup, and maintenance jobs
# Test monitoring script
./tools/monitor.sh --verbose
```

#### Email Notifications
```bash
# Test email configuration
./tools/monitor.sh --test-email

# Check SMTP settings in settings.json if emails fail
```

### Backup Verification

#### Test Backup Creation
```bash
# Manual database backup
./tools/db-backup.sh

# Manual full system backup
./tools/create-full-backup.sh

# Check backup location
ls -la /var/lib/*/backups/
```

#### Test Backup Restoration
```bash
# Test restore process (dry run)
./tools/restore.sh --dry-run

# Verify backup integrity
./tools/db-backup.sh --validate
```

## Advanced Configuration

### OCI Vault Integration

#### Setup OCI CLI
```bash
# Install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Configure OCI CLI
oci setup config

# Test configuration
oci iam region list
```

#### Migrate to OCI Vault
```bash
# Run OCI setup script
./tools/oci-setup.sh

# Upload existing configuration to vault
./tools/update-secrets.sh --upload-to-oci

# Verify OCI Vault configuration
./startup.sh --validate
```

### Custom Domain Configuration

#### Multiple Domains
Edit `caddy/Caddyfile`:
```caddy
vault.example.com, passwords.example.com {
    reverse_proxy vaultwarden:8080

    # Include Cloudflare IP restrictions
    import /etc/caddy-extra/cloudflare-ips.caddy

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
    }
}
```

#### SSL Certificate Management
```bash
# Force certificate renewal (if needed)
docker compose exec caddy caddy reload

# Check certificate status
docker compose exec caddy caddy list-certificates
```

### Performance Tuning

#### Resource Adjustment
Edit `docker-compose.yml`:
```yaml
# For larger teams (10+ users)
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
# Schedule regular maintenance
# Already included in cron jobs by default

# Manual database maintenance
./tools/sqlite-maintenance.sh --full

# Database performance analysis
./tools/sqlite-maintenance.sh --analyze
```

## Troubleshooting Deployment Issues

### Common Installation Problems

#### Docker Installation Fails
```bash
# Manual Docker installation
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add user to docker group
usermod -aG docker $USER
systemctl enable --now docker
```

#### Permission Errors
```bash
# Fix ownership of project directory
chown -R root:root /opt/VaultWarden-OCI-Minimal

# Fix settings.json permissions
chmod 600 settings.json
chown root:root settings.json
```

#### Port Conflicts
```bash
# Check for port conflicts
netstat -tlnp | grep -E ':80|:443'

# Stop conflicting services
systemctl stop apache2 nginx

# Disable conflicting services
systemctl disable apache2 nginx
```

### Startup Problems

#### Container Fails to Start
```bash
# Check container status
docker compose ps

# View detailed logs
docker compose logs vaultwarden
docker compose logs caddy

# Check disk space
df -h

# Check memory usage
free -h
```

#### Database Connection Issues
```bash
# Check database file permissions
ls -la /var/lib/*/data/bwdata/db.sqlite3

# Test database integrity
./tools/sqlite-maintenance.sh --check

# Reset database (DESTRUCTIVE - backup first!)
rm /var/lib/*/data/bwdata/db.sqlite3
./startup.sh
```

#### SSL Certificate Problems
```bash
# Check Caddy logs
docker compose logs caddy

# Test domain resolution
nslookup vault.example.com

# Check Cloudflare proxy status
dig vault.example.com

# Manual certificate request
docker compose exec caddy caddy reload
```

### Network Issues

#### Cannot Access Web Interface
```bash
# Check if services are running
docker compose ps

# Test local connectivity
curl -I http://localhost:80
curl -k -I https://localhost:443

# Check firewall rules
ufw status
iptables -L

# Test from external location
curl -I https://vault.example.com
```

#### Fail2ban Not Working
```bash
# Check fail2ban status
systemctl status fail2ban

# Check jail configuration
fail2ban-client status vaultwarden

# View fail2ban logs
tail -f /var/log/fail2ban.log

# Restart fail2ban
systemctl restart fail2ban
```

## Maintenance Procedures

### Regular Maintenance Tasks

#### Weekly Checks
```bash
# System health check
./tools/monitor.sh --verbose

# Check disk usage
df -h

# Review recent logs
docker compose logs --since 7d | grep -i error
```

#### Monthly Tasks
```bash
# Update system packages
apt update && apt upgrade

# Container updates (handled by Watchtower automatically)
# Manual update if needed:
docker compose pull
./startup.sh

# Security audit
fail2ban-client status
ufw status
```

#### Quarterly Tasks
```bash
# Rotate admin token
nano settings.json  # Update ADMIN_TOKEN
./startup.sh

# Test backup restoration
./tools/restore.sh --dry-run

# Review and update configurations
nano settings.json
./startup.sh --validate
```

### Update Procedures

#### Application Updates
```bash
# Watchtower handles this automatically
# Manual update process:
docker compose pull
docker compose up -d --remove-orphans

# Verify after update
docker compose ps
curl -I https://vault.example.com
```

#### System Updates
```bash
# Update Ubuntu packages
apt update && apt upgrade -y

# Reboot if kernel updated
reboot

# Verify services after reboot
./startup.sh --validate
```

### Backup and Recovery

#### Create Manual Backup
```bash
# Full system backup
./tools/create-full-backup.sh

# Database only backup
./tools/db-backup.sh

# Configuration backup
cp settings.json settings.json.backup.$(date +%Y%m%d)
```

#### Disaster Recovery
```bash
# On new server, after basic setup:
1. Install VaultWarden-OCI-Minimal
2. Run: ./tools/restore.sh /path/to/backup.tar.gz
3. Verify: ./startup.sh --validate
4. Test: Access web interface
```

This deployment guide ensures a smooth and secure installation process while providing comprehensive troubleshooting and maintenance procedures for ongoing operations.
