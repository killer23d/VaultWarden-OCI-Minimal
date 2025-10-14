# Maintenance Guide

## Overview

VaultWarden-OCI-Minimal is designed as a "set and forget" system with comprehensive automated maintenance. This guide covers both automated maintenance tasks and manual procedures for optimal system performance and reliability.

## Automated Maintenance System

### Cron Schedule Overview

The system automatically installs the following maintenance schedule during `init-setup.sh`:

```bash
# Database maintenance
0 2 * * 1    root   cd /opt/VaultWarden-OCI-Minimal && ./tools/sqlite-maintenance.sh -t full
0 6 * * *    root   cd /opt/VaultWarden-OCI-Minimal && ./tools/sqlite-maintenance.sh -t quick

# System monitoring (every 5 minutes)
*/5 * * * *  root   cd /opt/VaultWarden-OCI-Minimal && ./tools/monitor.sh

# Backup jobs
0 1 * * *    root   cd /opt/VaultWarden-OCI-Minimal && ./tools/db-backup.sh
0 0 * * 0    root   cd /opt/VaultWarden-OCI-Minimal && ./tools/create-full-backup.sh

# Infrastructure maintenance
0 3 * * *    root   cd /opt/VaultWarden-OCI-Minimal && ./tools/update-cloudflare-ips.sh --quiet
0 4 * * *    root   find /var/lib/*/logs -name "*.log" -size +50M -exec truncate -s 10M {} \;
0 4 * * *    root   find /var/lib/*/backups -name "*.backup*" -mtime +30 -delete
```

### Task Breakdown

#### Database Maintenance
- **Full Maintenance** (Weekly - Monday 2:00 AM)
  - SQLite VACUUM operation
  - Database integrity check
  - Index optimization
  - Statistics update
  - Corruption detection and repair

- **Quick Maintenance** (Daily - 6:00 AM)
  - Basic integrity check
  - Performance statistics update
  - Log analysis
  - Space usage monitoring

#### System Monitoring
- **Health Checks** (Every 5 minutes)
  - Container health validation
  - Service availability testing
  - Resource usage monitoring
  - Automatic recovery attempts
  - Alert generation for failures

#### Backup Operations
- **Database Backup** (Daily - 1:00 AM)
  - Multi-format database backups
  - Encryption and compression
  - Integrity verification
  - Retention policy enforcement

- **Full System Backup** (Weekly - Sunday 12:00 AM)
  - Complete system archive
  - Configuration backup
  - SSL certificate backup
  - Log file inclusion

#### Infrastructure Maintenance
- **Cloudflare IP Updates** (Daily - 3:00 AM)
  - Fetch current IP ranges
  - Update Caddy configuration
  - Reload proxy configuration
  - Validate connectivity

- **Log Management** (Daily - 4:00 AM)
  - Rotate large log files (>50MB)
  - Compress old logs
  - Clean temporary files
  - Maintain disk space

- **Backup Cleanup** (Daily - 4:00 AM)
  - Remove expired backups (>30 days)
  - Compress older archives
  - Maintain storage limits
  - Generate cleanup reports

## Manual Maintenance Procedures

### Database Maintenance

#### Database Health Check
```bash
# Quick database status
./tools/sqlite-maintenance.sh --check

# Detailed database analysis
./tools/sqlite-maintenance.sh --analyze

# Full integrity verification
./tools/sqlite-maintenance.sh --verify
```

#### Database Optimization
```bash
# Full maintenance (includes VACUUM)
./tools/sqlite-maintenance.sh --full

# Quick optimization only
./tools/sqlite-maintenance.sh --quick

# Rebuild indexes
./tools/sqlite-maintenance.sh --reindex

# Update query statistics
./tools/sqlite-maintenance.sh --analyze-only
```

#### Database Performance Tuning
```bash
# Check database size and fragmentation
./tools/sqlite-maintenance.sh --stats

# Monitor query performance
./tools/sqlite-maintenance.sh --explain-queries

# Optimize for read-heavy workload
./tools/sqlite-maintenance.sh --optimize-reads
```

### System Health Monitoring

#### Health Check Commands
```bash
# Comprehensive system health check
./tools/monitor.sh --verbose

# Quick status overview
./tools/monitor.sh --summary

# Test all critical functions
./tools/monitor.sh --test-all

# Generate health report
./tools/monitor.sh --report
```

#### Resource Monitoring
```bash
# Check disk usage
./tools/monitor.sh --disk-usage

# Monitor memory consumption
./tools/monitor.sh --memory-usage

# Check container resource usage
./tools/monitor.sh --container-stats

# Network connectivity tests
./tools/monitor.sh --network-tests
```

#### Service Management
```bash
# Restart failed services
./tools/monitor.sh --restart-failed

# Validate all service health
./tools/monitor.sh --validate-services

# Check service logs for errors
./tools/monitor.sh --check-logs

# Test external dependencies
./tools/monitor.sh --test-dependencies
```

### Container Maintenance

#### Container Updates
```bash
# Check for available updates
docker compose pull

# Update containers (handled by Watchtower automatically)
# Manual update if needed:
docker compose up -d --remove-orphans

# Verify updates
docker compose ps
./startup.sh --validate
```

#### Container Cleanup
```bash
# Remove unused containers
docker container prune -f

# Remove unused images
docker image prune -f

# Remove unused volumes (careful!)
docker volume prune -f

# Remove unused networks
docker network prune -f

# Complete cleanup
docker system prune -f
```

#### Container Health Monitoring
```bash
# Check container health status
docker compose ps

# View container resource usage
docker stats --no-stream

# Check container logs
docker compose logs --tail 100

# Inspect container configuration
docker compose config
```

### Log Management

#### Log Analysis
```bash
# View recent VaultWarden logs
docker compose logs --tail 100 vaultwarden

# Check for error patterns
docker compose logs | grep -i error

# Monitor real-time logs
docker compose logs -f

# Analyze access patterns
tail -f /var/lib/*/logs/caddy/access.log
```

#### Log Rotation and Cleanup
```bash
# Manual log rotation
./tools/monitor.sh --rotate-logs

# Clean up old logs
find /var/lib/*/logs -name "*.log" -mtime +7 -delete

# Compress large logs
find /var/lib/*/logs -name "*.log" -size +10M -exec gzip {} \;

# Check log disk usage
du -sh /var/lib/*/logs/
```

### Configuration Management

#### Configuration Validation
```bash
# Validate current configuration
./startup.sh --validate

# Check configuration syntax
jq . settings.json

# Verify Docker Compose configuration
docker compose config

# Test Caddy configuration
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

#### Configuration Updates
```bash
# Backup current configuration
./tools/backup-current-config.sh

# Update configuration
nano settings.json

# Validate changes
./startup.sh --validate

# Apply changes
./startup.sh
```

#### Security Configuration Review
```bash
# Check file permissions
find /var/lib/*/ -type f -not -perm 600 -not -perm 644 -not -perm 755

# Verify SSL configuration
docker compose exec caddy caddy list-certificates

# Check firewall rules
ufw status verbose

# Review fail2ban status
fail2ban-client status
```

## Maintenance Schedules

### Daily Tasks (Automated)

#### Automatic Daily Maintenance
- **1:00 AM**: Database backup creation
- **3:00 AM**: Cloudflare IP range updates
- **4:00 AM**: Log rotation and cleanup
- **6:00 AM**: Quick database maintenance
- **Every 5 min**: Health monitoring and auto-recovery

#### Manual Daily Checks (Optional)
```bash
# Morning health check (5 minutes)
./tools/monitor.sh --summary
docker compose ps
df -h

# Evening review (10 minutes)
./tools/monitor.sh --backup-status
tail -n 50 /var/log/fail2ban.log
```

### Weekly Tasks

#### Automated Weekly Maintenance
- **Sunday 12:00 AM**: Full system backup
- **Monday 2:00 AM**: Full database maintenance

#### Manual Weekly Reviews (15 minutes)
```bash
# System health review
./tools/monitor.sh --weekly-report

# Security review
fail2ban-client status
grep "WARN\|ERROR" /var/lib/*/logs/vaultwarden/*.log

# Performance review
./tools/sqlite-maintenance.sh --stats
du -sh /var/lib/*/
```

### Monthly Tasks

#### Container Updates (Automated)
- **First Monday 4:00 AM**: Watchtower container updates

#### Manual Monthly Maintenance (30 minutes)
```bash
# System updates
sudo apt update && sudo apt upgrade

# Security audit
./tools/monitor.sh --security-audit

# Configuration review
./startup.sh --validate
./tools/backup-current-config.sh

# Performance optimization
./tools/sqlite-maintenance.sh --full --analyze

# Backup verification
./tools/restore.sh --test --latest
```

### Quarterly Tasks (Manual)

#### Comprehensive Review (2 hours)
```bash
# Security review
- Review and update admin tokens
- Audit user access and permissions
- Update Cloudflare security settings
- Review firewall rules and fail2ban configuration

# Performance optimization
- Analyze database growth patterns
- Review resource usage trends
- Optimize container resource limits
- Clean up unused Docker resources

# Disaster recovery testing
- Test full backup restoration
- Verify off-site backup accessibility
- Update disaster recovery procedures
- Train team on recovery procedures

# Documentation updates
- Update configuration documentation
- Review and update operational procedures
- Update contact information
- Document any configuration changes
```

## Maintenance Tools

### Built-in Maintenance Scripts

#### Database Maintenance Tool
```bash
# ./tools/sqlite-maintenance.sh options:
--check          # Quick integrity check
--full           # Complete maintenance (VACUUM, etc.)
--quick          # Fast optimization only
--analyze        # Update query statistics
--stats          # Show database statistics
--verify         # Deep integrity verification
--reindex        # Rebuild all indexes
--explain        # Analyze query performance
```

#### Monitoring Tool
```bash
# ./tools/monitor.sh options:
--summary        # Quick status overview
--verbose        # Detailed health information
--test-all       # Run all available tests
--backup-status  # Check backup system health
--disk-usage     # Disk space analysis
--memory-usage   # Memory consumption analysis
--restart-failed # Restart any failed services
--report         # Generate comprehensive report
```

#### Backup Tools
```bash
# Database backup tool
./tools/db-backup.sh [--format binary|sql|json|csv] [--validate]

# Full system backup tool
./tools/create-full-backup.sh [--include-logs] [--name custom-name]

# Restore tool
./tools/restore.sh [--dry-run] [--test] [backup-file]
```

### Maintenance Logging

#### Log Files Location
```bash
# System maintenance logs
/var/log/syslog                    # General system logs
/var/log/cron.log                  # Cron job execution logs

# Application logs
/var/lib/*/logs/vaultwarden/       # VaultWarden application logs
/var/lib/*/logs/caddy/            # Caddy proxy logs
/var/lib/*/logs/fail2ban/         # Fail2ban security logs

# Maintenance script logs
# Scripts log to syslog with identifiers:
journalctl -t sqlite-maintenance
journalctl -t monitor
journalctl -t backup
```

#### Log Analysis Commands
```bash
# Recent maintenance activity
journalctl --since "1 day ago" -t sqlite-maintenance -t monitor -t backup

# Failed maintenance tasks
journalctl --since "1 week ago" --priority=err

# Cron job status
grep CRON /var/log/syslog | tail -20

# Backup job results
journalctl -t backup --since "1 week ago"
```

## Troubleshooting Maintenance Issues

### Common Maintenance Problems

#### Database Maintenance Failures
```bash
# Check database locks
./tools/sqlite-maintenance.sh --check-locks

# Force unlock database (if safe)
./tools/sqlite-maintenance.sh --force-unlock

# Repair corrupted database
./tools/sqlite-maintenance.sh --repair

# Restore from backup if corruption is severe
./tools/restore.sh --database-only --latest
```

#### Backup Failures
```bash
# Check backup disk space
df -h /var/lib/*/backups/

# Test backup creation
./tools/db-backup.sh --dry-run --verbose

# Verify backup encryption
./tools/db-backup.sh --test-encryption

# Check GPG configuration
gpg --list-keys
```

#### Container Update Issues
```bash
# Check Watchtower logs
docker compose logs watchtower

# Manual update with error checking
docker compose pull
docker compose up -d --remove-orphans
./startup.sh --validate

# Rollback if needed
docker compose down
docker tag backup-image:latest current-image:latest
./startup.sh
```

#### Cron Job Failures
```bash
# Check cron service status
systemctl status cron

# Verify cron jobs are installed
crontab -l

# Test cron job execution
sudo -u root bash -c "cd /opt/VaultWarden-OCI-Minimal && ./tools/monitor.sh"

# Check cron job permissions
ls -la /opt/VaultWarden-OCI-Minimal/tools/
```

This comprehensive maintenance system ensures reliable, automated operation of your VaultWarden deployment with minimal manual intervention required.
