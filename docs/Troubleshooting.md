# Troubleshooting Guide

## Overview

This comprehensive troubleshooting guide covers common issues, diagnostic procedures, and resolution steps for VaultWarden-OCI-Minimal. The guide is organized by symptom and includes both automatic recovery options and manual intervention procedures.

## General Troubleshooting Approach

### Debug Mode Activation

#### Enable Comprehensive Debug Output
```bash
# Enable debug mode for any script
export DEBUG=1

# Examples with debug output
DEBUG=1 ./startup.sh
DEBUG=1 ./tools/monitor.sh
DEBUG=1 ./tools/init-setup.sh
```

#### Debug Mode Features
- **Verbose Logging**: Detailed step-by-step execution information
- **Variable Inspection**: Display of configuration values and paths
- **Command Tracing**: Show actual commands being executed
- **Error Context**: Enhanced error messages with context
- **Timing Information**: Performance and timing details

### Diagnostic Information Collection

#### System Information Gathering
```bash
# Collect comprehensive system diagnostics
./tools/monitor.sh --diagnostic > system_diagnostic.txt

# Manual diagnostic collection
cat << 'EOF' > collect_diagnostics.sh
#!/bin/bash
echo "=== System Information ==="
uname -a
cat /etc/os-release
free -h
df -h

echo "=== Docker Information ==="
docker --version
docker compose version
docker system info

echo "=== Container Status ==="
docker compose ps
docker compose logs --tail 50

echo "=== Network Status ==="
ss -tlnp | grep -E ':80|:443'
curl -I https://google.com

echo "=== Configuration Status ==="
ls -la settings.json
./startup.sh --validate

echo "=== Log Summary ==="
tail -20 /var/lib/*/logs/vaultwarden/*.log
EOF

chmod +x collect_diagnostics.sh
./collect_diagnostics.sh
```

## Installation and Setup Issues

### Installation Failures

#### Issue: Docker Installation Fails
**Symptoms:**
- "Docker not found" after running init-setup.sh
- Package installation errors
- Permission denied errors

**Diagnosis:**
```bash
# Check if Docker is installed
which docker
docker --version

# Check Docker service status
systemctl status docker

# Check for installation errors
journalctl -u docker --since "1 hour ago"
```

**Resolution:**
```bash
# Manual Docker installation
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add user to Docker group
usermod -aG docker $USER
newgrp docker

# Start and enable Docker service
systemctl enable --now docker

# Verify installation
docker run hello-world
```

#### Issue: Package Dependencies Missing
**Symptoms:**
- "jq command not found"
- "curl not available" 
- Script execution failures

**Diagnosis:**
```bash
# Check for missing packages
which jq curl openssl fail2ban

# Check package installation status
dpkg -l | grep -E "jq|curl|openssl|fail2ban"
```

**Resolution:**
```bash
# Update package index
apt update

# Install missing packages
apt install -y jq curl openssl fail2ban ufw gettext

# Retry setup
./tools/init-setup.sh
```

#### Issue: Permission Errors During Setup
**Symptoms:**
- "Permission denied" when creating files
- Cannot write to /var/lib/ or /etc/
- File ownership errors

**Diagnosis:**
```bash
# Check current user and permissions
whoami
id

# Check target directory permissions
ls -ld /var/lib /etc/systemd/system
```

**Resolution:**
```bash
# Ensure running as root
sudo su -

# Fix ownership of project directory
chown -R root:root /opt/VaultWarden-OCI-Minimal

# Retry setup as root
sudo ./tools/init-setup.sh
```

### Configuration Issues

#### Issue: settings.json Not Created or Invalid
**Symptoms:**
- "Configuration file not found"
- JSON parsing errors
- Invalid configuration warnings

**Diagnosis:**
```bash
# Check if settings.json exists
ls -la settings.json

# Validate JSON syntax
jq . settings.json

# Check file permissions
ls -la settings.json
```

**Resolution:**
```bash
# Re-create configuration from example
cp settings.json.example settings.json

# Fix JSON syntax errors
nano settings.json

# Set proper permissions
chmod 600 settings.json
chown root:root settings.json

# Validate configuration
./startup.sh --validate
```

#### Issue: Environment Variable Problems
**Symptoms:**
- Variables not exported correctly
- Docker Compose cannot find variables
- Configuration not loaded

**Diagnosis:**
```bash
# Check environment variables
printenv | grep -E "DOMAIN|ADMIN_TOKEN|PROJECT"

# Test configuration loading
source lib/config.sh
_load_configuration
```

**Resolution:**
```bash
# Manually source configuration
source lib/config.sh

# Force configuration reload
unset CONFIG_LOADED
_load_configuration

# Restart with clean environment
./startup.sh
```

## Service Startup Issues

### Container Startup Failures

#### Issue: VaultWarden Container Won't Start
**Symptoms:**
- Container exits immediately
- "Health check failing" messages
- Database connection errors

**Diagnosis:**
```bash
# Check container status
docker compose ps vaultwarden

# View container logs
docker compose logs vaultwarden

# Check container configuration
docker compose config | grep -A 20 vaultwarden

# Test container manually
docker run --rm -it vaultwarden/server:latest /bin/bash
```

**Resolution:**
```bash
# Check database file permissions
ls -la /var/lib/*/data/bwdata/
chown -R 1000:1000 /var/lib/*/data/bwdata/

# Reset database if corrupted
./tools/sqlite-maintenance.sh --repair

# Restart container
docker compose restart vaultwarden

# Full service restart
./startup.sh
```

#### Issue: Caddy SSL Certificate Problems
**Symptoms:**
- SSL certificate errors in browser
- "Certificate not found" in logs
- ACME challenge failures

**Diagnosis:**
```bash
# Check Caddy logs for certificate errors
docker compose logs caddy | grep -i certificate

# Check domain DNS resolution
nslookup vault.example.com

# Verify domain accessibility from internet
curl -I http://vault.example.com

# Check Caddy configuration
docker compose exec caddy caddy list-certificates
```

**Resolution:**
```bash
# Verify domain points to server
dig vault.example.com

# Check ports 80/443 are accessible
nc -zv vault.example.com 80
nc -zv vault.example.com 443

# Force certificate renewal
docker compose exec caddy caddy reload

# Reset Caddy data if needed
docker compose down
docker volume rm caddy_data
./startup.sh
```

#### Issue: Fail2ban Service Problems
**Symptoms:**
- Fail2ban not starting
- "Cannot bind to socket" errors
- Jail configuration failures

**Diagnosis:**
```bash
# Check fail2ban status
docker compose logs fail2ban

# Check host fail2ban conflicts
systemctl status fail2ban

# Verify network mode
docker compose config | grep -A 5 fail2ban
```

**Resolution:**
```bash
# Stop host fail2ban service if running
systemctl stop fail2ban
systemctl disable fail2ban

# Restart fail2ban container
docker compose restart fail2ban

# Check jail status
docker compose exec fail2ban fail2ban-client status
```

### Network and Connectivity Issues

#### Issue: Cannot Access Web Interface
**Symptoms:**
- "Connection refused" in browser
- Timeout errors when connecting
- "Site can't be reached" messages

**Diagnosis:**
```bash
# Test local connectivity
curl -I http://localhost:80
curl -I https://localhost:443

# Check if ports are listening
ss -tlnp | grep -E ':80|:443'

# Test external connectivity
curl -I http://YOUR_SERVER_IP

# Check firewall rules
ufw status verbose
iptables -L -n
```

**Resolution:**
```bash
# Check container port mappings
docker compose ps
docker port $(docker compose ps -q caddy)

# Verify firewall allows traffic
ufw allow 80/tcp
ufw allow 443/tcp
ufw reload

# Test with disabled firewall (temporarily)
ufw --force disable
curl -I http://YOUR_SERVER_IP
ufw --force enable

# Restart networking
systemctl restart networking
./startup.sh
```

#### Issue: DNS Resolution Problems
**Symptoms:**
- Domain doesn't resolve
- "Name not found" errors
- SSL certificate validation fails

**Diagnosis:**
```bash
# Test DNS resolution
nslookup vault.example.com
dig vault.example.com

# Check with different DNS servers
nslookup vault.example.com 8.8.8.8
nslookup vault.example.com 1.1.1.1

# Verify DNS propagation
dig vault.example.com @8.8.8.8
dig vault.example.com @1.1.1.1
```

**Resolution:**
```bash
# Update DNS settings
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Flush DNS cache
systemctl restart systemd-resolved

# Wait for DNS propagation (up to 24-48 hours)
# Verify from external location

# Use IP address temporarily
curl -H "Host: vault.example.com" http://YOUR_SERVER_IP
```

## Runtime and Performance Issues

### Database Issues

#### Issue: SQLite Database Corruption
**Symptoms:**
- "Database disk image is malformed"
- Data inconsistency errors
- Application crashes on database access

**Diagnosis:**
```bash
# Check database integrity
./tools/sqlite-maintenance.sh --check

# Detailed integrity check
./tools/sqlite-maintenance.sh --verify

# Check database file
ls -la /var/lib/*/data/bwdata/db.sqlite3
file /var/lib/*/data/bwdata/db.sqlite3
```

**Resolution:**
```bash
# Stop VaultWarden
docker compose stop vaultwarden

# Backup current database
cp /var/lib/*/data/bwdata/db.sqlite3 /var/lib/*/data/bwdata/db.sqlite3.corrupted

# Attempt repair
./tools/sqlite-maintenance.sh --repair

# If repair fails, restore from backup
./tools/restore.sh --database-only --latest

# Restart services
./startup.sh
```

#### Issue: Database Performance Problems
**Symptoms:**
- Slow web interface response
- Timeout errors
- High CPU usage

**Diagnosis:**
```bash
# Check database statistics
./tools/sqlite-maintenance.sh --stats

# Monitor database performance
./tools/sqlite-maintenance.sh --explain-queries

# Check system resources
top -p $(pgrep -f vaultwarden)
iostat -x 1 5
```

**Resolution:**
```bash
# Optimize database
./tools/sqlite-maintenance.sh --full

# Update statistics
./tools/sqlite-maintenance.sh --analyze

# Check for lock issues
./tools/sqlite-maintenance.sh --check-locks

# Consider increasing resources
# Edit docker-compose.yml memory limits
```

### Resource Exhaustion

#### Issue: Disk Space Full
**Symptoms:**
- "No space left on device" errors
- Container startup failures
- Backup failures

**Diagnosis:**
```bash
# Check disk usage
df -h

# Find largest files/directories
du -sh /* 2>/dev/null | sort -hr
du -sh /var/lib/* 2>/dev/null | sort -hr

# Check VaultWarden specific usage
du -sh /var/lib/*/
du -sh /var/lib/*/logs/
du -sh /var/lib/*/backups/
```

**Resolution:**
```bash
# Clean up logs
find /var/lib/*/logs -name "*.log" -size +50M -exec truncate -s 10M {} \;

# Clean up old backups
find /var/lib/*/backups -name "*.gpg" -mtime +30 -delete

# Clean Docker resources
docker system prune -f
docker volume prune -f

# Compress large files
find /var/lib/*/logs -name "*.log" -size +10M -exec gzip {} \;

# Move backups to external storage
# Configure backup upload to cloud storage
```

#### Issue: Memory Exhaustion
**Symptoms:**
- Out of memory errors
- Container killing (OOMKilled)
- System slowdown

**Diagnosis:**
```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head -10

# Check container memory usage
docker stats --no-stream

# Check for memory leaks
pmap -d $(pgrep -f vaultwarden)
```

**Resolution:**
```bash
# Increase container memory limits
# Edit docker-compose.yml:
# memory: 1G (increase from 512M)

# Add swap if needed
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Restart containers with new limits
./startup.sh

# Monitor memory usage
watch -n 5 'free -h && docker stats --no-stream'
```

## Security and Authentication Issues

### Authentication Problems

#### Issue: Admin Panel Access Denied
**Symptoms:**
- "Invalid admin token" messages
- Cannot access /admin endpoint
- Authentication failures

**Diagnosis:**
```bash
# Check admin token
jq -r '.ADMIN_TOKEN' settings.json

# Verify token is not empty
[[ -n "$(jq -r '.ADMIN_TOKEN' settings.json)" ]] && echo "Token exists" || echo "Token missing"

# Check VaultWarden logs for auth errors
docker compose logs vaultwarden | grep -i admin
```

**Resolution:**
```bash
# Generate new admin token
NEW_TOKEN=$(openssl rand -base64 32)

# Update configuration
jq --arg token "$NEW_TOKEN" '.ADMIN_TOKEN = $token' settings.json > settings.json.tmp
mv settings.json.tmp settings.json
chmod 600 settings.json

# Restart services
./startup.sh

# Access admin panel with new token
echo "New admin token: $NEW_TOKEN"
```

#### Issue: User Login Failures
**Symptoms:**
- Users cannot log in
- "Invalid credentials" errors
- Database authentication errors

**Diagnosis:**
```bash
# Check VaultWarden logs
docker compose logs vaultwarden | grep -i "login\|auth"

# Check database connectivity
./tools/sqlite-maintenance.sh --check

# Verify user exists in database
echo "SELECT email FROM users;" | sqlite3 /var/lib/*/data/bwdata/db.sqlite3
```

**Resolution:**
```bash
# Reset user password via admin panel
# Or create new user account

# Check SMTP configuration for password reset
grep SMTP settings.json

# Verify email functionality
./tools/monitor.sh --test-email

# Clear browser cache and cookies
# Try from different browser/device
```

### SSL/TLS Issues

#### Issue: SSL Certificate Errors
**Symptoms:**
- "Certificate not valid" warnings
- "Connection not secure" messages
- Certificate chain problems

**Diagnosis:**
```bash
# Check certificate details
openssl s_client -connect vault.example.com:443 -servername vault.example.com

# Check certificate expiration
echo | openssl s_client -connect vault.example.com:443 2>/dev/null | openssl x509 -noout -dates

# Verify certificate chain
curl -I https://vault.example.com
```

**Resolution:**
```bash
# Force certificate renewal
docker compose exec caddy caddy reload

# Check domain accessibility from internet
curl -I http://vault.example.com
# Must be accessible for ACME validation

# Reset certificate data if needed
docker compose down
docker volume rm caddy_data
./startup.sh

# Wait for certificate generation (5-10 minutes)
```

## Backup and Recovery Issues

### Backup Failures

#### Issue: Database Backup Fails
**Symptoms:**
- "Backup creation failed" errors
- GPG encryption errors
- Insufficient disk space for backups

**Diagnosis:**
```bash
# Test backup creation
./tools/db-backup.sh --dry-run --verbose

# Check backup directory permissions
ls -ld /var/lib/*/backups/

# Check GPG configuration
gpg --list-keys

# Check disk space
df -h /var/lib/*/backups/
```

**Resolution:**
```bash
# Fix backup directory permissions
chmod 700 /var/lib/*/backups/
chown root:root /var/lib/*/backups/

# Test GPG encryption
echo "test" | gpg --symmetric --batch --passphrase "test123" --cipher-algo AES256

# Free up disk space
find /var/lib/*/backups -name "*.gpg" -mtime +30 -delete

# Retry backup
./tools/db-backup.sh --verbose
```

#### Issue: Restore Process Fails
**Symptoms:**
- "Cannot restore from backup" errors
- Backup file corruption
- Permission denied during restore

**Diagnosis:**
```bash
# Test backup integrity
./tools/db-backup.sh --verify /path/to/backup.gpg

# Check restore permissions
ls -la /var/lib/*/data/

# Test GPG decryption
gpg --decrypt --batch --passphrase "$BACKUP_PASSPHRASE" backup.gpg
```

**Resolution:**
```bash
# Stop services before restore
docker compose down

# Fix data directory permissions
chown -R 1000:1000 /var/lib/*/data/

# Use interactive restore
./tools/restore.sh

# Verify restoration
./startup.sh --validate
```

## Monitoring and Alerting Issues

### Monitoring System Problems

#### Issue: Health Checks Failing
**Symptoms:**
- Continuous "unhealthy" status
- False positive alerts
- Monitoring script errors

**Diagnosis:**
```bash
# Run monitoring with verbose output
./tools/monitor.sh --verbose

# Check specific health checks
./tools/monitor.sh --containers
./tools/monitor.sh --services
./tools/monitor.sh --resources
```

**Resolution:**
```bash
# Fix specific issues identified by monitoring
# Common fixes:

# Restart failed containers
docker compose restart

# Clean up resources
docker system prune -f

# Fix file permissions
./tools/monitor.sh --fix-permissions

# Update monitoring thresholds if too sensitive
# Edit monitoring script thresholds
```

#### Issue: Email Alerts Not Working
**Symptoms:**
- No email notifications received
- SMTP connection errors
- Email delivery failures

**Diagnosis:**
```bash
# Test SMTP configuration
./tools/monitor.sh --test-email

# Check SMTP settings
grep SMTP settings.json

# Test SMTP connectivity
telnet smtp.gmail.com 587
```

**Resolution:**
```bash
# Update SMTP configuration
nano settings.json

# For Gmail, use App Password
# Generate at: https://myaccount.google.com/apppasswords

# Test email sending
echo "Test message" | mail -s "VaultWarden Test" admin@example.com

# Check mail logs
tail -f /var/log/mail.log
```

## Advanced Troubleshooting

### Log Analysis

#### Centralized Log Review
```bash
# Create comprehensive log analysis script
cat << 'EOF' > analyze_logs.sh
#!/bin/bash
echo "=== Error Analysis (Last 24 Hours) ==="
find /var/lib/*/logs -name "*.log" -mtime -1 -exec grep -l -i error {} \; | while read log; do
    echo "=== Errors in $log ==="
    grep -i error "$log" | tail -10
    echo
done

echo "=== Authentication Issues ==="
docker compose logs vaultwarden | grep -i "auth\|login" | tail -20

echo "=== Certificate Issues ==="
docker compose logs caddy | grep -i "certificate\|tls\|ssl" | tail -10

echo "=== Resource Issues ==="
docker compose logs | grep -i -E "memory\|disk\|space" | tail -10
EOF

chmod +x analyze_logs.sh
./analyze_logs.sh
```

### Performance Analysis

#### System Performance Debugging
```bash
# Monitor system performance during issues
cat << 'EOF' > performance_debug.sh
#!/bin/bash
echo "=== System Performance Analysis ==="
echo "Load Average:"
uptime

echo "Memory Usage:"
free -h

echo "Disk Usage:"
df -h

echo "Top Processes:"
ps aux --sort=-%cpu | head -10

echo "Container Stats:"
docker stats --no-stream

echo "Network Connections:"
ss -tlnp | grep -E ':80|:443'

echo "Database Performance:"
./tools/sqlite-maintenance.sh --stats
EOF

chmod +x performance_debug.sh
./performance_debug.sh
```

### Recovery Procedures

#### Emergency Recovery Script
```bash
# Create emergency recovery script
cat << 'EOF' > emergency_recovery.sh
#!/bin/bash
set -e

echo "=== VaultWarden Emergency Recovery ==="

echo "Step 1: Stop all services"
docker compose down

echo "Step 2: Backup current state"
mkdir -p /tmp/vaultwarden_emergency_backup
cp -r /var/lib/*/data /tmp/vaultwarden_emergency_backup/
cp settings.json /tmp/vaultwarden_emergency_backup/

echo "Step 3: Fix permissions"
chown -R root:root /opt/VaultWarden-OCI-Minimal
chown -R 1000:1000 /var/lib/*/data/bwdata/
chmod 600 settings.json

echo "Step 4: Validate configuration"
./startup.sh --validate

echo "Step 5: Start services"
./startup.sh

echo "Step 6: Health check"
sleep 30
./tools/monitor.sh --summary

echo "=== Recovery Complete ==="
echo "Backup location: /tmp/vaultwarden_emergency_backup"
EOF

chmod +x emergency_recovery.sh
```

This troubleshooting guide provides systematic approaches to identify and resolve issues while maintaining the system's reliability and the "set and forget" operational philosophy.
