# Security Guide

## Overview

VaultWarden-OCI-Minimal implements a defense-in-depth security model appropriate for small team deployments. This guide explains the security measures, best practices, and configurations to ensure a secure deployment.

## Security Architecture

### Defense Layers

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: Network Security                                       │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│ │ Cloudflare  │ │    UFW      │ │  Docker     │                │
│ │ DDoS/WAF    │ │  Firewall   │ │  Network    │                │
│ └─────────────┘ └─────────────┘ └─────────────┘                │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: Application Security                                   │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│ │    SSL/TLS  │ │ Fail2ban    │ │ VaultWarden │                │
│ │   Caddy     │ │ Intrusion   │ │   Auth      │                │
│ └─────────────┘ └─────────────┘ └─────────────┘                │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Data Security                                          │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│ │ File Perms  │ │ Encryption  │ │   Secret    │                │
│ │   600/755   │ │   Backups   │ │ Management  │                │
│ └─────────────┘ └─────────────┘ └─────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

## Network Security

### Firewall Configuration (UFW)

The init-setup script automatically configures UFW with minimal required rules:

```bash
# Default policies
ufw default deny incoming
ufw default allow outgoing

# Required services
ufw allow ssh                    # SSH access (port 22)
ufw allow 80/tcp                # HTTP (Caddy redirect to HTTPS)
ufw allow 443/tcp               # HTTPS (main application access)
```

### Cloudflare Integration

#### DDoS Protection
- **Automatic**: Built-in DDoS protection at Cloudflare edge
- **Rate Limiting**: Configurable rate limits per IP/endpoint
- **Geographic Blocking**: Block traffic from specific countries
- **Bot Management**: Automatic bot detection and mitigation

#### Web Application Firewall (WAF)
```bash
# Cloudflare WAF Rules (configure in dashboard)
- Block common attack patterns
- SQL injection protection  
- XSS protection
- File inclusion protection
- Comment spam protection
```

#### IP Allowlisting
Caddy automatically restricts access to Cloudflare IPs only:
```bash
# Updated automatically by update-cloudflare-ips.sh
remote_ip 173.245.48.0/20
remote_ip 103.21.244.0/22
# ... additional Cloudflare IP ranges
```

### Fail2ban Configuration

#### Automatic IP Blocking
- **VaultWarden Protection**: Monitors authentication failures
- **Caddy Protection**: Monitors proxy access logs
- **SSH Protection**: Monitors SSH login attempts
- **Custom Rules**: Configurable thresholds and ban times

#### Cloudflare Integration
When configured, banned IPs are also blocked at Cloudflare edge:
```bash
# Configure in settings.json
{
  "CLOUDFLARE_EMAIL": "your-email@example.com",
  "CLOUDFLARE_API_KEY": "your-global-api-key"
}
```

## Application Security

### SSL/TLS Configuration

#### Automatic Certificate Management
Caddy handles SSL certificates automatically:
- **Let's Encrypt**: Automatic certificate provisioning
- **Auto-Renewal**: Certificates renewed before expiration
- **OCSP Stapling**: Improved certificate validation performance
- **HTTP/2**: Modern protocol support

#### Security Headers
```bash
# Automatically configured by Caddy
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'
```

#### Cipher Suites
Caddy uses secure defaults:
- **TLS 1.2+**: Minimum supported version
- **ECDHE**: Perfect forward secrecy
- **AES-GCM**: Authenticated encryption
- **ChaCha20-Poly1305**: Modern encryption for mobile devices

### VaultWarden Authentication

#### Multi-Factor Authentication (MFA)
- **TOTP**: Time-based one-time passwords
- **WebAuthn**: Hardware security keys (YubiKey, etc.)
- **Duo**: Integration with Duo Security (enterprise)
- **Email**: Email-based 2FA (basic)

#### Password Policies
```json
{
  "PASSWORD_ITERATIONS": 100000,
  "PASSWORD_HINTS_ALLOWED": false,
  "SHOW_PASSWORD_HINT": false,
  "DOMAIN": "https://your-vault.com",
  "SIGNUPS_ALLOWED": false
}
```

#### Session Management
- **Secure Cookies**: HttpOnly, Secure, SameSite attributes
- **Session Timeout**: Configurable timeout periods
- **Device Management**: Track and revoke device sessions
- **IP Validation**: Optional IP-based session binding

## Data Security

### File System Permissions

#### Configuration Files
```bash
# Sensitive configuration
/path/to/project/settings.json                    (600, root:root)
/etc/systemd/system/project-name.env             (600, root:root)
/etc/caddy-extra/cloudflare-ips.caddy           (644, root:root)

# Application directories
/var/lib/project-name/                           (755, root:root)
/var/lib/project-name/data/                      (755, 33:33)
/var/lib/project-name/backups/                   (700, root:root)
/var/lib/project-name/logs/                      (755, root:root)
```

#### Validation Script
```bash
#!/bin/bash
# Check file permissions
find /var/lib/project-name -type f -not -perm 600 -not -perm 644 -not -perm 755
find /path/to/project -name "settings.json" -not -perm 600
```

### Secret Management

#### Local Configuration (settings.json)
- **Encryption**: File encrypted at rest (optional)
- **Permissions**: 600 (owner read/write only)
- **Backup**: Automated versioned backups
- **Validation**: JSON schema validation

#### OCI Vault Integration
```bash
# Environment setup
export OCI_SECRET_OCID="ocid1.vaultsecret.oc1..."

# Automatic loading
source lib/config.sh
_load_configuration  # Loads from OCI Vault if OCID is set
```

#### Runtime Security
- **Memory Only**: Secrets loaded into memory, not written to disk
- **No Environment**: Secrets not exposed in process environment
- **Automatic Cleanup**: Memory cleared on script exit
- **Audit Trail**: Access logging in OCI Vault

### Backup Encryption

#### GPG Encryption
All backups are encrypted using GPG:
```bash
# Backup creation with encryption
./tools/db-backup.sh
# Creates: backup_20241014_120000.sql.gz.gpg

# Decryption (restore process)
gpg --decrypt --batch --passphrase "$BACKUP_PASSPHRASE" backup.sql.gz.gpg | gunzip
```

#### Encryption Configuration
```json
{
  "BACKUP_PASSPHRASE": "generated-secure-passphrase",
  "BACKUP_ENCRYPTION_CIPHER": "AES256",
  "BACKUP_COMPRESSION": "gzip"
}
```

## Container Security

### Resource Isolation

#### Memory Limits
```yaml
# Prevents memory exhaustion attacks
services:
  vaultwarden:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
```

#### CPU Limits
```yaml
# Prevents CPU starvation
services:
  vaultwarden:
    deploy:
      resources:
        limits:
          cpus: '1.0'
        reservations:
          cpus: '0.5'
```

#### Network Isolation
```yaml
# Isolated network per deployment
networks:
  default:
    name: ${COMPOSE_PROJECT_NAME}_network
    driver: bridge
    internal: false  # Allows internet access
```

### Container Updates

#### Automated Updates (Watchtower)
```yaml
# Secure update configuration
watchtower:
  command:
    - --cleanup              # Remove old images
    - --rolling-restart      # Zero-downtime updates
    - --label-enable         # Only update labeled containers
    - --stop-timeout=120s    # Graceful shutdown
```

#### Update Schedule
- **Frequency**: Monthly (first Monday at 4 AM)
- **Notifications**: Email alerts for updates
- **Rollback**: Automatic rollback on health check failure
- **Testing**: Staging environment recommended

## Security Monitoring

### Log Analysis

#### Fail2ban Monitoring
```bash
# Check banned IPs
sudo fail2ban-client status vaultwarden
sudo fail2ban-client status caddy

# View ban log
tail -f /var/log/fail2ban.log
```

#### VaultWarden Audit Logs
```bash
# Authentication events
docker compose logs vaultwarden | grep -i "auth"

# Admin panel access
docker compose logs vaultwarden | grep -i "admin"

# Failed login attempts
docker compose logs vaultwarden | grep -i "failed"
```

#### Caddy Access Logs
```bash
# Access patterns
tail -f /var/lib/project-name/logs/caddy/access.log

# Error analysis
tail -f /var/lib/project-name/logs/caddy/error.log

# Security events
grep "403\|404\|429" /var/lib/project-name/logs/caddy/access.log
```

### Security Metrics

#### Health Monitoring
The monitoring system tracks security-relevant metrics:
- **Failed Authentication Attempts**: Rate and patterns
- **Unusual Access Patterns**: Geographic or time-based anomalies
- **Resource Usage**: Potential DoS indicators
- **Certificate Status**: SSL certificate validity and renewal

#### Alerting Thresholds
```bash
# Configure in monitoring script
FAILED_AUTH_THRESHOLD=10      # Per 5-minute window
RESOURCE_USAGE_THRESHOLD=80   # CPU/Memory percentage
DISK_USAGE_THRESHOLD=90       # Disk space percentage
CERT_EXPIRY_WARNING=30        # Days before expiration
```

## Incident Response

### Security Event Classification

#### Critical (Immediate Response)
- **Successful Breach**: Unauthorized admin access
- **Data Exfiltration**: Unusual data export patterns
- **System Compromise**: Container or host compromise
- **DDoS Attack**: Service unavailability

#### High (4-hour Response)
- **Multiple Failed Logins**: Potential brute force
- **Suspicious Access Patterns**: Unusual geographic access
- **Certificate Issues**: SSL certificate problems
- **Resource Exhaustion**: System performance impact

#### Medium (24-hour Response)
- **Failed Authentication**: Single failed login attempts
- **Rate Limiting**: Automatic rate limit triggers
- **Update Failures**: Automated update failures
- **Backup Issues**: Backup creation or validation failures

### Response Procedures

#### Immediate Actions
1. **Isolate**: Block suspicious IPs via Cloudflare or fail2ban
2. **Assess**: Determine scope and impact of incident
3. **Contain**: Prevent further unauthorized access
4. **Preserve**: Secure logs and evidence for investigation

#### Investigation Steps
1. **Log Analysis**: Review all relevant log files
2. **Timeline**: Establish sequence of events
3. **Impact Assessment**: Determine what data/systems were affected
4. **Root Cause**: Identify how the incident occurred

#### Recovery Actions
1. **Secure**: Close attack vectors and patch vulnerabilities
2. **Restore**: Restore systems/data from clean backups if needed
3. **Monitor**: Enhanced monitoring during recovery period
4. **Validate**: Ensure systems are clean and functioning properly

## Security Best Practices

### Admin User Management

#### Admin Account Security
- **Strong Password**: Use password manager for admin password
- **MFA Required**: Enable multi-factor authentication
- **Regular Rotation**: Change admin token quarterly
- **Access Logging**: Monitor all admin panel access

#### User Management
```bash
# Disable user registration
"SIGNUPS_ALLOWED": false

# Require email verification
"SIGNUPS_VERIFY": true

# Limit org invitations
"INVITATIONS_ALLOWED": true
"INVITATION_EXPIRATION_HOURS": 120
```

### Network Security

#### SSH Hardening
```bash
# /etc/ssh/sshd_config recommendations
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

#### Cloudflare Security Settings
- **Security Level**: High or I'm Under Attack mode
- **Challenge Passage**: 30 minutes
- **Browser Integrity Check**: Enabled
- **Always Use HTTPS**: Enabled
- **Minimum TLS Version**: 1.2
- **Opportunistic Encryption**: Enabled

### Backup Security

#### Secure Backup Storage
- **Encryption**: Always encrypt backups before storage
- **Access Control**: Limit access to backup storage
- **Geographic Separation**: Store backups in different region
- **Regular Testing**: Test backup restoration monthly

#### Backup Validation
```bash
# Automated backup validation
./tools/db-backup.sh --validate
./tools/create-full-backup.sh --test-restore
```

### System Hardening

#### Operating System
```bash
# Automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades

# Disable unnecessary services
sudo systemctl disable bluetooth cups avahi-daemon

# Enable audit logging
sudo apt install auditd
sudo systemctl enable auditd
```

#### Docker Security
```bash
# Docker daemon security
{
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

## Compliance Considerations

### Data Protection

#### GDPR Compliance
- **Data Minimization**: Only collect necessary data
- **Right to Erasure**: Ability to delete user data
- **Data Portability**: Export user data in standard formats
- **Audit Trail**: Log all data access and modifications

#### Data Retention
```bash
# Configurable retention periods
BACKUP_RETENTION_DAYS=30
LOG_RETENTION_DAYS=90
AUDIT_RETENTION_DAYS=365
```

### Security Standards

#### Industry Best Practices
- **NIST Cybersecurity Framework**: Identify, Protect, Detect, Respond, Recover
- **CIS Controls**: Implementation of relevant CIS security controls
- **OWASP Top 10**: Protection against common web application vulnerabilities
- **ISO 27001**: Information security management principles

#### Regular Security Reviews
- **Monthly**: Review failed authentication logs
- **Quarterly**: Update security configurations and test backups
- **Annually**: Full security audit and penetration testing
- **Continuous**: Automated security monitoring and alerting

This security guide ensures that VaultWarden-OCI-Minimal maintains strong security posture appropriate for small team deployments while remaining manageable and not over-engineered.
