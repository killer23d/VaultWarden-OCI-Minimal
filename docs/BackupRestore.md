# Backup and Restore Guide

## Overview

VaultWarden-OCI-Minimal implements a comprehensive, automated backup system designed for small team deployments. The system provides multiple backup formats, encryption, and automated retention management while maintaining simplicity and reliability.

## Backup System Architecture

### Backup Types

#### 1. Database Backups (Daily)
- **Frequency**: Every day at 1:00 AM
- **Formats**: Binary (.db), SQL (.sql), JSON (.json), CSV (.csv)
- **Encryption**: GPG encrypted with configurable passphrase
- **Compression**: gzip compression for space efficiency
- **Location**: `/var/lib/{project-name}/backups/database/`

#### 2. Full System Backups (Weekly)
- **Frequency**: Every Sunday at 12:00 AM
- **Contents**: Database, configuration files, SSL certificates, logs
- **Format**: Encrypted tar.gz archive
- **Location**: `/var/lib/{project-name}/backups/full/`

#### 3. Configuration Backups (On-Demand)
- **Trigger**: Before configuration changes
- **Contents**: settings.json and related config files
- **Location**: `/var/lib/{project-name}/config-backups/`

### Automated Retention Policy

```bash
# Default retention periods (configurable)
Database Backups: 30 days
Full System Backups: 90 days  
Configuration Backups: 365 days
Log Files: 7 days (rotated)
```

## Database Backup Operations

### Manual Database Backup

#### Basic Database Backup
```bash
# Create database backup with all formats
./tools/db-backup.sh

# Output files:
# - backup_YYYYMMDD_HHMMSS.db.gz.gpg      (Binary SQLite)
# - backup_YYYYMMDD_HHMMSS.sql.gz.gpg     (SQL dump)
# - backup_YYYYMMDD_HHMMSS.json.gz.gpg    (JSON export)
# - backup_YYYYMMDD_HHMMSS.csv.gz.gpg     (CSV export)
```

#### Specific Format Backup
```bash
# Binary format only (fastest)
./tools/db-backup.sh --format binary

# SQL format only (most compatible)  
./tools/db-backup.sh --format sql

# JSON format (human readable)
./tools/db-backup.sh --format json

# CSV format (spreadsheet compatible)
./tools/db-backup.sh --format csv
```

#### Advanced Options
```bash
# Validate backup after creation
./tools/db-backup.sh --validate

# Test backup without creating files
./tools/db-backup.sh --dry-run

# Backup with custom encryption
./tools/db-backup.sh --passphrase "custom-passphrase"

# Quiet mode (no output except errors)
./tools/db-backup.sh --quiet
```

### Backup Verification

#### Integrity Checking
```bash
# Verify backup integrity
./tools/db-backup.sh --verify /path/to/backup.db.gz.gpg

# Test restore without actually restoring
./tools/restore.sh --test /path/to/backup.tar.gz

# Validate all recent backups
find /var/lib/*/backups -name "*.gpg" -mtime -7 -exec ./tools/db-backup.sh --verify {} \;
```

#### Backup Status Report
```bash
# Generate backup status report
./tools/monitor.sh --backup-status

# Check backup disk usage
du -sh /var/lib/*/backups/

# List recent backups
ls -la /var/lib/*/backups/database/ | head -10
```

## Full System Backup Operations

### Manual Full System Backup

#### Complete System Backup
```bash
# Create full system backup
./tools/create-full-backup.sh

# Output: full_backup_YYYYMMDD_HHMMSS.tar.gz.gpg
```

#### Custom Full Backup
```bash
# Include specific directories
./tools/create-full-backup.sh --include-logs

# Exclude certain files
./tools/create-full-backup.sh --exclude-cache

# Custom backup name
./tools/create-full-backup.sh --name "pre-migration-backup"
```

### Full Backup Contents

#### Standard Inclusions
```
/var/lib/{project-name}/
├── data/bwdata/              # VaultWarden database and attachments
├── caddy_data/              # SSL certificates and Caddy data
├── caddy_config/            # Caddy configuration cache
└── config-backups/          # Configuration file history

/project-root/
├── settings.json            # Main configuration (encrypted)
├── caddy/                   # Proxy configuration
├── fail2ban/               # Security configuration  
└── ddclient/               # DDNS configuration
```

#### Optional Inclusions
```bash
# Include recent logs (last 7 days)
--include-logs

# Include Docker images (for air-gapped restore)
--include-images

# Include system configuration
--include-system
```

## Restore Operations

### Interactive Restore Process

#### Guided Restoration
```bash
# Start interactive restore wizard
./tools/restore.sh

# The wizard will:
# 1. List available backups
# 2. Verify backup integrity  
# 3. Stop running services
# 4. Restore data and configuration
# 5. Restart services
# 6. Validate restoration
```

#### Direct Backup Restore
```bash
# Restore from specific backup file
./tools/restore.sh /path/to/backup.tar.gz

# Restore database only
./tools/restore.sh --database-only /path/to/db_backup.sql.gz.gpg

# Restore configuration only
./tools/restore.sh --config-only /path/to/config_backup.tar.gz
```

### Advanced Restore Options

#### Selective Restoration
```bash
# Restore to specific date/time
./tools/restore.sh --restore-point "2024-10-14 12:00:00"

# Restore with different project name
./tools/restore.sh --project-name "new-vault-name" backup.tar.gz

# Dry run (show what would be restored)
./tools/restore.sh --dry-run backup.tar.gz
```

#### Cross-Server Restoration
```bash
# On target server after setup
1. ./tools/init-setup.sh
2. ./tools/restore.sh /path/to/transferred/backup.tar.gz
3. ./startup.sh --validate
4. Access web interface to verify
```

## Backup Configuration

### Encryption Settings

#### Backup Passphrase Configuration
```json
{
  "BACKUP_PASSPHRASE": "your-secure-passphrase-here",
  "BACKUP_ENCRYPTION_CIPHER": "AES256",
  "BACKUP_COMPRESSION_LEVEL": "6"
}
```

#### GPG Encryption Details
- **Algorithm**: AES256 symmetric encryption
- **Key Derivation**: PBKDF2 with high iteration count
- **Compression**: gzip level 6 (balanced speed/size)
- **Integrity**: SHA-256 checksums for all backups

### Retention Configuration

#### Custom Retention Periods
Edit cron jobs or create `/etc/vaultwarden-backup.conf`:
```bash
# Backup retention configuration
DATABASE_RETENTION_DAYS=30
FULL_BACKUP_RETENTION_DAYS=90
CONFIG_BACKUP_RETENTION_DAYS=365
LOG_RETENTION_DAYS=7

# Storage limits
MAX_BACKUP_SIZE_GB=10
BACKUP_CLEANUP_HOUR=4
```

#### Storage Management
```bash
# Check backup storage usage
./tools/monitor.sh --storage-report

# Clean old backups manually
find /var/lib/*/backups -name "*.gpg" -mtime +30 -delete

# Compress old backups
find /var/lib/*/backups -name "*.tar.gz" -mtime +7 -exec xz {} \;
```

## Automated Backup Monitoring

### Backup Health Checks

#### Monitoring Integration
The monitoring system automatically:
- **Verifies** backup completion and integrity
- **Alerts** on backup failures or missing backups
- **Reports** storage usage and retention status
- **Tests** restore capabilities monthly

#### Health Check Commands
```bash
# Check backup system health
./tools/monitor.sh --backup-health

# Test backup and restore cycle
./tools/monitor.sh --test-backup-restore

# Generate backup report
./tools/create-full-backup.sh --report-only
```

### Backup Alerts

#### Email Notifications
Configure SMTP in settings.json for backup alerts:
```json
{
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_FROM": "backups@yourdomain.com", 
  "ADMIN_EMAIL": "admin@yourdomain.com"
}
```

#### Alert Conditions
- **Critical**: Backup failure, corruption detected
- **Warning**: Storage space low, retention policy exceeded
- **Info**: Backup completed successfully, cleanup performed

## Disaster Recovery Procedures

### Complete System Recovery

#### Recovery Scenario 1: Data Corruption
```bash
# 1. Stop services
docker compose down

# 2. Restore from latest backup
./tools/restore.sh --latest --database-only

# 3. Verify restoration
./tools/sqlite-maintenance.sh --check

# 4. Restart services
./startup.sh
```

#### Recovery Scenario 2: Full Server Loss
```bash
# On new server:
# 1. Basic setup
sudo apt update && sudo apt upgrade -y

# 2. Install VaultWarden-OCI-Minimal
git clone <repository-url>
cd VaultWarden-OCI-Minimal
sudo ./tools/init-setup.sh --auto

# 3. Transfer and restore backup
./tools/restore.sh /path/to/transferred/backup.tar.gz

# 4. Validate and start
./startup.sh --validate
```

#### Recovery Scenario 3: Rollback to Previous Version
```bash
# 1. Create current backup
./tools/create-full-backup.sh --name "pre-rollback"

# 2. Restore previous backup
./tools/restore.sh --restore-point "2024-10-13 23:59:59"

# 3. Verify functionality
curl -I https://vault.example.com
```

### Recovery Time Objectives (RTO)

| Scenario | Recovery Time | Requirements |
|----------|---------------|--------------|
| Database Corruption | 15-30 minutes | Latest database backup |
| Configuration Loss | 5-15 minutes | Configuration backup |
| Full Server Loss | 2-4 hours | Full system backup + new server |
| Disaster Recovery | 4-8 hours | Off-site backup + new infrastructure |

## Backup Best Practices

### Security Practices

#### Backup Security
- **Encrypt all backups** with strong passphrases
- **Store passphrases securely** (password manager, vault)
- **Use separate storage locations** for backup copies
- **Test backup restoration regularly** (monthly)
- **Verify backup integrity** before relying on backups

#### Access Control
```bash
# Proper backup file permissions
chmod 600 /var/lib/*/backups/*.gpg
chown root:root /var/lib/*/backups/

# Secure backup directories
chmod 700 /var/lib/*/backups/
chmod 700 /var/lib/*/config-backups/
```

### Storage Strategies

#### Local Storage (Default)
- **Pros**: Fast backup/restore, no network dependencies
- **Cons**: Single point of failure, limited disaster recovery
- **Recommendation**: Combine with off-site storage

#### Off-Site Storage Integration
```bash
# Example: Upload to cloud storage (configure in cron)
# Add to backup script:
# aws s3 cp backup.tar.gz.gpg s3://your-backup-bucket/
# rclone copy backup.tar.gz.gpg remote:backup-folder/
# scp backup.tar.gz.gpg backup-server:/backups/
```

#### 3-2-1 Backup Strategy
- **3** copies of important data
- **2** different storage media/locations
- **1** copy stored off-site

### Operational Practices

#### Regular Testing
```bash
# Monthly restore test (automated)
# Add to cron:
# 0 2 15 * * root cd /opt/VaultWarden-OCI-Minimal && ./tools/restore.sh --test --latest

# Quarterly full recovery test
# 1. Build new test server
# 2. Restore from production backup  
# 3. Verify all functionality
# 4. Document any issues
```

#### Backup Validation
- **Immediate**: Verify backup creation and encryption
- **Daily**: Check backup file integrity and size
- **Weekly**: Test restore process on sample files
- **Monthly**: Full restoration test on test environment

#### Documentation
- **Maintain** current backup/restore procedures
- **Document** recovery scenarios and tested procedures  
- **Update** contact information for emergency recovery
- **Train** team members on restoration procedures

This comprehensive backup and restore system ensures data protection and rapid recovery capabilities appropriate for small team VaultWarden deployments.
