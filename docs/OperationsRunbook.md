# Operations Runbook

## Overview

This operations runbook provides systematic procedures for managing VaultWarden-OCI-Minimal in production. It covers daily operations, incident response, maintenance procedures, and escalation paths designed for small team operations while maintaining enterprise-grade reliability.

## Daily Operations

### Morning Health Check (5 minutes)

#### Quick System Status
```bash
# Navigate to project directory
cd /opt/VaultWarden-OCI-Minimal

# Quick health overview
./tools/monitor.sh --summary

# Expected output:
# ✅ All containers healthy
# ✅ Database accessible 
# ✅ SSL certificate valid
# ✅ Backup system operational
# ✅ Disk space sufficient (XX% used)
# ✅ Memory usage normal (XXX MB)
```

#### Container Status Verification
```bash
# Check all container status
docker compose ps

# Expected status for all containers:
# vaultwarden: Up (healthy)
# caddy: Up (healthy) 
# fail2ban: Up
# watchtower: Up
# ddclient: Up (if enabled)
```

#### Access Verification
```bash
# Test web interface accessibility
curl -I https://vault.yourdomain.com

# Expected response:
# HTTP/2 200
# server: Caddy
# Cloudflare headers (if using Cloudflare)
```

#### Issue Escalation
If any checks fail:
1. **Container Issues**: Check logs and attempt restart
2. **Network Issues**: Verify DNS and firewall
3. **Certificate Issues**: Check Caddy logs and domain accessibility
4. **Database Issues**: Run integrity check and backup validation

### Evening Review (10 minutes)

#### Security Review
```bash
# Check fail2ban status
docker compose exec fail2ban fail2ban-client status

# Review recent ban activity
docker compose logs fail2ban | grep -i "ban\|unban" | tail -20

# Check authentication logs
docker compose logs vaultwarden | grep -i "login\|auth" | tail -20
```

#### Backup Status Check
```bash
# Verify today's backup completion
./tools/monitor.sh --backup-status

# Check backup storage usage
du -sh /var/lib/*/backups/

# Verify latest backup integrity
ls -la /var/lib/*/backups/database/ | head -5
```

#### Performance Review
```bash
# Check system resource usage
./tools/monitor.sh --resources

# Review any performance alerts
journalctl --since today -p warning | grep -E "vaultwarden|monitor|backup"
```

## Weekly Operations

### Monday Morning Review (30 minutes)

#### Comprehensive Health Assessment
```bash
# Full system health report
./tools/monitor.sh --comprehensive > weekly_health_$(date +%Y%m%d).txt

# Database maintenance verification
./tools/sqlite-maintenance.sh --stats

# Backup system validation
./tools/restore.sh --test --latest

# Security audit
fail2ban-client status
ufw status verbose
```

#### Performance Analysis
```bash
# Database performance review
./tools/sqlite-maintenance.sh --analyze

# Resource usage trends
# Check disk usage growth
df -h
du -sh /var/lib/*/ | sort -hr

# Memory usage patterns
free -h
docker stats --no-stream
```

#### Log Review and Analysis
```bash
# Weekly log analysis
./analyze_logs.sh > weekly_logs_$(date +%Y%m%d).txt

# Error pattern analysis
find /var/lib/*/logs -name "*.log" -mtime -7 -exec grep -l -i error {} \;

# Security event review
grep -i "blocked\|banned\|failed" /var/lib/*/logs/fail2ban/*.log | wc -l
```

### Friday Afternoon Preparation (15 minutes)

#### Weekend Readiness Check
```bash
# Verify automated systems
crontab -l | grep -E "monitor|backup|maintenance"

# Check disk space projections
./tools/monitor.sh --disk-usage --verbose

# Test alert systems
./tools/monitor.sh --test-email

# Verify backup retention
find /var/lib/*/backups -name "*.gpg" | wc -l
```

#### Documentation Updates
```bash
# Update operational notes
echo "$(date): Weekly review completed, all systems nominal" >> operations_log.txt

# Record any configuration changes
git log --since="1 week ago" --oneline

# Update contact information if needed
grep -E "ADMIN_EMAIL|SMTP" settings.json
```

## Incident Response Procedures

### Service Outage Response

#### Severity 1: Complete Service Outage
**Detection:** Web interface completely inaccessible, all containers down

**Immediate Response (0-5 minutes):**
```bash
# 1. Assess scope of outage
docker compose ps
curl -I https://vault.yourdomain.com

# 2. Check system resources
df -h
free -h
uptime

# 3. Attempt quick recovery
./startup.sh

# 4. If startup fails, investigate
docker compose logs --tail 50
systemctl status docker
```

**Investigation (5-15 minutes):**
```bash
# 1. Collect diagnostic information
./collect_diagnostics.sh > incident_$(date +%Y%m%d_%H%M%S).txt

# 2. Check for obvious causes
journalctl --since "1 hour ago" -p err
dmesg | tail -50

# 3. Resource exhaustion check
iotop -ao1
ps aux --sort=-%cpu | head -10
```

**Recovery Actions:**
```bash
# If disk space issue:
find /var/lib/*/logs -name "*.log" -size +50M -exec truncate -s 10M {} \;
docker system prune -f

# If memory issue:
echo 3 > /proc/sys/vm/drop_caches
docker compose restart

# If configuration issue:
cp settings.json.backup settings.json
./startup.sh --validate

# If database corruption:
./tools/restore.sh --database-only --latest
```

#### Severity 2: Partial Service Degradation
**Detection:** Slow response times, intermittent failures, some features unavailable

**Response Procedure:**
```bash
# 1. Identify affected components
./tools/monitor.sh --verbose

# 2. Performance analysis
./performance_debug.sh

# 3. Targeted restart of affected services
docker compose restart vaultwarden
# or
docker compose restart caddy

# 4. Monitor recovery
watch -n 30 './tools/monitor.sh --summary'
```

#### Severity 3: Minor Issues or Warnings
**Detection:** Alerts received, but service generally functional

**Response Procedure:**
```bash
# 1. Log the issue
echo "$(date): Minor issue detected - $(./tools/monitor.sh --summary)" >> issues_log.txt

# 2. Schedule maintenance window
# Plan resolution during low-usage period

# 3. Prepare remediation
# Research issue and prepare fix

# 4. Monitor for escalation
# Ensure issue doesn't worsen
```

### Security Incident Response

#### Suspected Unauthorized Access
**Detection Indicators:**
- Unusual fail2ban activity
- Unexpected admin panel access
- New user registrations (if disabled)
- Unusual database activity

**Immediate Response:**
```bash
# 1. Document current state
./tools/monitor.sh --security-audit > security_incident_$(date +%Y%m%d_%H%M%S).txt

# 2. Check recent authentication
docker compose logs vaultwarden | grep -i "login\|auth\|admin" | tail -50

# 3. Review fail2ban logs
docker compose logs fail2ban | tail -100

# 4. Check for unauthorized changes
find /opt/VaultWarden-OCI-Minimal -type f -mtime -1 -exec ls -la {} \;
```

**Investigation and Response:**
```bash
# 1. Rotate admin token immediately
NEW_TOKEN=$(openssl rand -base64 32)
jq --arg token "$NEW_TOKEN" '.ADMIN_TOKEN = $token' settings.json > settings.json.tmp
mv settings.json.tmp settings.json
chmod 600 settings.json
./startup.sh

# 2. Force all user re-authentication
# (Requires admin panel access)

# 3. Review and strengthen security
ufw status verbose
fail2ban-client status
docker compose logs | grep -i -E "attack|intrusion|suspicious"

# 4. Create incident report
# Document timeline, impact, and response actions
```

## Maintenance Windows

### Planned Maintenance Procedures

#### Monthly System Updates
**Timing:** First Sunday of each month, 2:00 AM - 4:00 AM

**Pre-Maintenance Checklist:**
```bash
# 1. Create full backup
./tools/create-full-backup.sh --name "pre-update-$(date +%Y%m%d)"

# 2. Verify backup integrity
./tools/restore.sh --test /var/lib/*/backups/full/full_backup_*.tar.gz.gpg

# 3. Document current state
./tools/monitor.sh --comprehensive > pre_update_state_$(date +%Y%m%d).txt

# 4. Notify users (if applicable)
# Send maintenance notification email
```

**Update Procedure:**
```bash
# 1. Update system packages
apt update && apt upgrade -y

# 2. Update containers (Watchtower handles this automatically)
# Manual process if needed:
docker compose pull
docker compose up -d --remove-orphans

# 3. Verify services after updates
./startup.sh --validate
./tools/monitor.sh --test-all

# 4. Performance validation
curl -w "@curl-format.txt" -s -o /dev/null https://vault.yourdomain.com

# 5. Security verification
./tools/monitor.sh --security-check
```

**Post-Maintenance Validation:**
```bash
# 1. Full functionality test
# - Access web interface
# - Test user login
# - Verify vault synchronization
# - Test admin panel access

# 2. Performance verification
./tools/sqlite-maintenance.sh --stats
./tools/monitor.sh --resources

# 3. Security validation
fail2ban-client status
ufw status
docker compose logs | grep -i error | wc -l

# 4. Documentation
echo "$(date): Monthly maintenance completed successfully" >> maintenance_log.txt
```

#### Database Maintenance Window
**Timing:** Quarterly, Saturday 1:00 AM - 3:00 AM

**Procedure:**
```bash
# 1. Create database backup
./tools/db-backup.sh --format all --validate

# 2. Stop VaultWarden temporarily
docker compose stop vaultwarden

# 3. Comprehensive database maintenance
./tools/sqlite-maintenance.sh --full --analyze --verify

# 4. Restart and validate
docker compose start vaultwarden
sleep 60
./tools/monitor.sh --test-all

# 5. Performance comparison
./tools/sqlite-maintenance.sh --stats > post_maintenance_stats.txt
```

## Escalation Procedures

### Contact Information

#### Primary Contacts
```bash
# System Administrator
Name: [Your Name]
Email: admin@yourdomain.com
Phone: [Your Phone]
Availability: 24/7 for Severity 1 incidents

# Backup Administrator
Name: [Backup Admin]
Email: backup-admin@yourdomain.com
Phone: [Backup Phone]
Availability: Business hours, emergency on-call

# External Support
OCI Support: [If using OCI Vault]
Cloudflare Support: [If using Cloudflare]
DNS Provider: [Domain registrar support]
```

#### Escalation Matrix

| Severity | Response Time | Escalation Time | Contact Method |
|----------|---------------|-----------------|----------------|
| 1 - Critical | Immediate | 15 minutes | Phone + Email |
| 2 - High | 1 hour | 4 hours | Email + SMS |
| 3 - Medium | 4 hours | 24 hours | Email |
| 4 - Low | 24 hours | 72 hours | Email |

### External Dependencies

#### Service Dependencies
```bash
# Check external service status
curl -I https://status.cloudflare.com
curl -I https://status.docker.com
curl -I https://letsencrypt.org

# DNS provider status
nslookup yourdomain.com
dig yourdomain.com

# SMTP service status
telnet smtp.gmail.com 587
```

#### Vendor Support Contacts
- **Docker Support**: For container runtime issues
- **Cloudflare Support**: For DNS, SSL, or DDoS issues  
- **OCI Support**: For vault or compute issues
- **Domain Registrar**: For DNS delegation issues

## Monitoring and Alerting

### Alert Response Procedures

#### Critical Alerts
**Service Down Alert:**
```bash
# Immediate response within 5 minutes
1. Acknowledge alert
2. Run: ./tools/monitor.sh --verbose
3. Attempt: ./startup.sh
4. If failed: Escalate to Severity 1 incident
5. Document actions taken
```

**Database Corruption Alert:**
```bash
# Immediate response within 10 minutes
1. Stop writes: docker compose stop vaultwarden
2. Assess damage: ./tools/sqlite-maintenance.sh --check
3. Attempt repair: ./tools/sqlite-maintenance.sh --repair
4. If repair fails: ./tools/restore.sh --database-only --latest
5. Validate: ./startup.sh --validate
```

#### Warning Alerts
**High Resource Usage:**
```bash
# Response within 1 hour
1. Investigate cause: ./performance_debug.sh
2. Clean up if needed: docker system prune -f
3. Monitor trend: Watch resource usage for 24 hours
4. Schedule maintenance if persistent issue
```

**Backup Failure:**
```bash
# Response within 4 hours
1. Check disk space: df -h
2. Retry backup: ./tools/db-backup.sh --verbose
3. Fix underlying issue (permissions, disk space, etc.)
4. Verify backup system: ./tools/monitor.sh --backup-status
```

### Performance Monitoring

#### Key Performance Indicators (KPIs)
- **Availability**: >99.5% uptime target
- **Response Time**: <2 seconds for web interface
- **Database Performance**: <100ms average query time
- **Backup Success Rate**: 100% daily backup completion
- **Security**: <1% false positive rate for fail2ban

#### Performance Baselines
```bash
# Establish monthly performance baselines
./tools/sqlite-maintenance.sh --stats > baseline_$(date +%Y%m).txt
./tools/monitor.sh --resources >> baseline_$(date +%Y%m).txt
curl -w "@curl-format.txt" -s -o /dev/null https://vault.yourdomain.com >> baseline_$(date +%Y%m).txt
```

## Disaster Recovery

### Recovery Time Objectives (RTO)

| Scenario | Target RTO | Maximum RTO |
|----------|------------|-------------|
| Container restart | 5 minutes | 15 minutes |
| Database corruption | 30 minutes | 2 hours |
| Server failure | 4 hours | 8 hours |
| Complete disaster | 8 hours | 24 hours |

### Recovery Procedures

#### Server Rebuild Process
```bash
# On new server:
1. Basic system setup (Ubuntu 24.04 LTS)
2. Clone repository: git clone <repo-url>
3. Run setup: sudo ./tools/init-setup.sh --auto
4. Restore from backup: ./tools/restore.sh /path/to/backup.tar.gz
5. Validate operation: ./startup.sh --validate
6. Update DNS if IP changed
7. Test full functionality
```

#### Data Recovery Process
```bash
# Database-only recovery:
1. Stop VaultWarden: docker compose stop vaultwarden
2. Restore database: ./tools/restore.sh --database-only --latest
3. Verify integrity: ./tools/sqlite-maintenance.sh --check
4. Restart service: docker compose start vaultwarden
5. Test user access and data integrity
```

This operations runbook ensures systematic, reliable management of VaultWarden-OCI-Minimal while maintaining the "set and forget" operational philosophy with clear procedures for when manual intervention is required.
