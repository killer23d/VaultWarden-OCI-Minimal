# Monitoring Guide

## Overview

VaultWarden-OCI-Minimal includes a comprehensive monitoring system designed for proactive health management and automatic recovery. The monitoring system operates on a "self-healing" principle, attempting to resolve issues automatically before escalating to manual intervention.

## Monitoring Architecture

### Multi-Layer Monitoring

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: Container Health Checks (30-second intervals)         │
│ ├── VaultWarden HTTP endpoint monitoring                       │
│ ├── Caddy metrics endpoint validation                          │
│ ├── Fail2ban process verification                              │
│ └── Service dependency checking                                │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: Application Monitoring (5-minute intervals)           │
│ ├── Database connectivity and integrity                        │
│ ├── SSL certificate validity and expiration                    │
│ ├── Authentication system functionality                        │
│ └── Backup system health and completion                        │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: System Resource Monitoring (5-minute intervals)       │
│ ├── Disk space utilization and growth trends                   │
│ ├── Memory consumption and swap usage                          │
│ ├── CPU load and process monitoring                            │
│ └── Network connectivity and DNS resolution                    │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ Layer 4: External Dependency Monitoring (15-minute intervals)  │
│ ├── Internet connectivity validation                           │
│ ├── DNS resolution for configured domains                      │
│ ├── SMTP server accessibility (if configured)                  │
│ └── OCI Vault connectivity (if configured)                     │
└─────────────────────────────────────────────────────────────────┘
```

### Automated Recovery System

#### Self-Healing Capabilities
The monitoring system automatically attempts recovery for:
- **Container Failures**: Restart failed containers
- **Service Hangs**: Kill and restart unresponsive services  
- **Resource Exhaustion**: Clean temporary files and logs
- **Network Issues**: Reset network connections and DNS cache
- **Database Lock**: Resolve SQLite lock conflicts

#### Escalation Procedures
When automatic recovery fails:
1. **Retry**: Attempt recovery up to 3 times
2. **Log**: Record failure details and recovery attempts
3. **Alert**: Send email notification with diagnostic information
4. **Quarantine**: Prevent cascading failures by isolating problem

## Monitoring Components

### Container Health Monitoring

#### Docker Health Checks
All containers include built-in health checks:

```yaml
# VaultWarden health check
healthcheck:
  test: ["CMD", "curl", "-fsSL", "http://localhost:8080/alive"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 45s

# Caddy health check  
healthcheck:
  test: ["CMD", "curl", "-fsSL", "http://localhost:2019/metrics"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 20s
```

#### Container Status Monitoring
```bash
# Check all container health status
docker compose ps

# Monitor container resource usage
docker stats --no-stream

# View container health check logs
docker inspect --format='{{.State.Health}}' container_name
```

### Application Monitoring

#### VaultWarden Application Health
```bash
# Test web interface availability
curl -I https://vault.yourdomain.com

# Test API endpoint responsiveness
curl -s https://vault.yourdomain.com/api/config

# Check authentication system
curl -X POST https://vault.yourdomain.com/api/accounts/prelogin      -H "Content-Type: application/json"      -d '{"email":"test@example.com"}'
```

#### Database Health Monitoring
```bash
# Quick database connectivity test
./tools/sqlite-maintenance.sh --check

# Database integrity verification
./tools/sqlite-maintenance.sh --verify

# Performance metrics
./tools/sqlite-maintenance.sh --stats
```

#### SSL Certificate Monitoring
```bash
# Check certificate validity and expiration
openssl s_client -connect vault.yourdomain.com:443 -servername vault.yourdomain.com 2>/dev/null | openssl x509 -noout -dates

# Verify certificate through Caddy
docker compose exec caddy caddy list-certificates

# Check certificate auto-renewal
docker compose logs caddy | grep -i certificate
```

### System Resource Monitoring

#### Disk Space Monitoring
```bash
# Check overall disk usage
df -h

# Monitor VaultWarden data growth
du -sh /var/lib/*/data/

# Check backup storage usage
du -sh /var/lib/*/backups/

# Monitor log file sizes
du -sh /var/lib/*/logs/
```

#### Memory and CPU Monitoring
```bash
# System memory usage
free -h

# Process memory consumption
ps aux --sort=-%mem | head -10

# CPU load monitoring
uptime
top -bn1 | grep "load average"

# Container resource usage
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

#### Network Connectivity Monitoring
```bash
# Test external connectivity
ping -c 3 8.8.8.8

# DNS resolution testing
nslookup vault.yourdomain.com

# HTTP/HTTPS connectivity
curl -I https://vault.yourdomain.com
curl -I https://www.cloudflare.com/ips-v4
```

### External Dependency Monitoring

#### SMTP Server Monitoring
```bash
# Test SMTP connectivity
telnet smtp.gmail.com 587

# Test email sending capability
echo "Test email" | mail -s "VaultWarden Test" admin@yourdomain.com
```

#### OCI Vault Monitoring (if configured)
```bash
# Test OCI CLI connectivity
oci iam region list

# Verify vault access
oci vault secret get-secret-bundle --secret-id $OCI_SECRET_OCID --query 'data."secret-bundle-content".content'
```

## Automated Monitoring

### Cron-Based Monitoring

#### Monitoring Schedule
```bash
# System monitoring (every 5 minutes)
*/5 * * * * root cd /opt/VaultWarden-OCI-Minimal && ./tools/monitor.sh 2>&1 | logger -t monitor

# Health report generation (hourly)
0 * * * * root cd /opt/VaultWarden-OCI-Minimal && ./tools/monitor.sh --report 2>&1 | logger -t monitor-report

# Comprehensive health check (daily)
0 5 * * * root cd /opt/VaultWarden-OCI-Minimal && ./tools/monitor.sh --comprehensive 2>&1 | logger -t monitor-daily
```

#### Monitoring Script Options
```bash
# ./tools/monitor.sh command options:

# Basic monitoring
./tools/monitor.sh                    # Standard health check
./tools/monitor.sh --verbose          # Detailed output
./tools/monitor.sh --quiet            # Minimal output

# Specific checks
./tools/monitor.sh --containers       # Container health only
./tools/monitor.sh --services         # Service functionality
./tools/monitor.sh --resources        # System resources
./tools/monitor.sh --network          # Network connectivity

# Recovery actions
./tools/monitor.sh --restart-failed   # Restart failed services
./tools/monitor.sh --cleanup          # Clean temporary files
./tools/monitor.sh --fix-permissions  # Fix file permissions

# Reporting
./tools/monitor.sh --report           # Generate status report
./tools/monitor.sh --summary          # Quick status summary
./tools/monitor.sh --test-all         # Run all available tests
```

### Alert System

#### Email Notifications
Configure SMTP settings in `settings.json` for automated alerts:
```json
{
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_PORT": 587,
  "SMTP_SECURITY": "starttls",
  "SMTP_USERNAME": "notifications@yourdomain.com",
  "SMTP_PASSWORD": "your-app-password",
  "SMTP_FROM": "vaultwarden-alerts@yourdomain.com",
  "ADMIN_EMAIL": "admin@yourdomain.com"
}
```

#### Alert Conditions and Thresholds
```bash
# Critical alerts (immediate notification)
- Service failure lasting >15 minutes
- Database corruption detected
- Disk space >95% full
- SSL certificate expiration <7 days
- Backup failure for >24 hours

# Warning alerts (hourly digest)
- Container restart events
- High resource usage (>80% for >1 hour)
- Failed authentication attempts (>100/hour)
- Network connectivity issues
- Log file growth >1GB/day

# Info alerts (daily summary)
- Successful maintenance completion
- Performance statistics
- Resource usage trends
- Backup completion status
```

#### Alert Formats
```bash
# Critical Alert Example
Subject: [CRITICAL] VaultWarden Service Failure - vault.yourdomain.com
Body:
- Timestamp: 2024-10-14 12:30:00 UTC
- Service: vaultwarden container
- Issue: Health check failing for 15 minutes
- Recovery Attempts: 3 (all failed)
- Next Action: Manual intervention required
- Logs: See attached diagnostic information

# Warning Alert Example  
Subject: [WARNING] VaultWarden High Resource Usage - vault.yourdomain.com
Body:
- Timestamp: 2024-10-14 12:30:00 UTC
- Resource: Memory usage at 85%
- Duration: 90 minutes
- Trend: Increasing
- Recovery: Automatic cleanup scheduled
- Monitoring: Continued observation
```

## Manual Monitoring

### Health Check Commands

#### Comprehensive System Health
```bash
# Full system health check
./tools/monitor.sh --comprehensive

# Quick status overview
./tools/monitor.sh --summary

# Specific component checks
./tools/monitor.sh --containers --verbose
./tools/monitor.sh --database --verbose
./tools/monitor.sh --network --verbose
```

#### Diagnostic Commands
```bash
# Container diagnostics
docker compose ps
docker compose logs --tail 50

# System diagnostics
systemctl status docker
systemctl status fail2ban
systemctl status ufw

# Network diagnostics
ss -tlnp | grep -E ':80|:443|:22'
iptables -L -n | head -20
```

#### Performance Analysis
```bash
# Database performance
./tools/sqlite-maintenance.sh --analyze --stats

# System performance
iostat -x 1 5
vmstat 1 5
netstat -i

# Application performance
ab -n 100 -c 10 https://vault.yourdomain.com/
```

### Monitoring Dashboards

#### Command-Line Dashboard
```bash
# Create simple monitoring dashboard
watch -n 5 '
echo "=== VaultWarden System Status ==="
date
echo ""
echo "=== Containers ==="
docker compose ps
echo ""
echo "=== Resources ==="
df -h | grep -E "/$|/var"
free -h
echo ""
echo "=== Network ==="
curl -Is https://vault.yourdomain.com | head -1
'
```

#### Log Monitoring
```bash
# Real-time log monitoring
tail -f /var/lib/*/logs/vaultwarden/*.log &
tail -f /var/lib/*/logs/caddy/access.log &
tail -f /var/log/fail2ban.log &

# Log analysis commands
# Error pattern detection
grep -i error /var/lib/*/logs/vaultwarden/*.log | tail -10

# Access pattern analysis
awk '{print $1}' /var/lib/*/logs/caddy/access.log | sort | uniq -c | sort -nr | head -10

# Authentication monitoring
grep -i "login\|auth" /var/lib/*/logs/vaultwarden/*.log | tail -20
```

## Performance Monitoring

### Database Performance

#### Query Performance Monitoring
```bash
# Enable SQLite query logging (development only)
echo ".timer on" | sqlite3 /var/lib/*/data/bwdata/db.sqlite3

# Analyze slow queries
./tools/sqlite-maintenance.sh --explain-queries

# Monitor database growth
ls -lah /var/lib/*/data/bwdata/db.sqlite3
```

#### Database Metrics
```bash
# Database statistics
./tools/sqlite-maintenance.sh --stats

# Table size analysis
echo "SELECT name, COUNT(*) FROM sqlite_master WHERE type='table';" | sqlite3 /var/lib/*/data/bwdata/db.sqlite3

# Index usage analysis
echo "PRAGMA index_list(users);" | sqlite3 /var/lib/*/data/bwdata/db.sqlite3
```

### Application Performance

#### Response Time Monitoring
```bash
# Measure response times
time curl -s https://vault.yourdomain.com > /dev/null

# Load testing (use carefully)
ab -n 10 -c 2 https://vault.yourdomain.com/

# Connection testing
curl -w "@curl-format.txt" -s -o /dev/null https://vault.yourdomain.com
```

#### Resource Usage Trends
```bash
# Memory usage over time
while true; do
  echo "$(date): $(docker stats --no-stream --format 'table {{.Container}}	{{.MemUsage}}' | grep vaultwarden)"
  sleep 300
done

# Disk usage growth tracking
while true; do
  echo "$(date): $(du -sh /var/lib/*/data/)"
  sleep 3600
done
```

## Troubleshooting with Monitoring

### Common Monitoring Scenarios

#### Service Health Issues
```bash
# Diagnose container problems
docker compose logs vaultwarden | tail -100
docker inspect vaultwarden_container | jq .State

# Check resource constraints
docker stats --no-stream vaultwarden_container
free -h && df -h

# Network connectivity testing
docker compose exec vaultwarden curl -I http://localhost:8080/alive
```

#### Performance Degradation
```bash
# Identify performance bottlenecks
./tools/sqlite-maintenance.sh --analyze
top -p $(pgrep -f vaultwarden)

# Check for resource saturation
iostat -x 1 5
sar -r 1 5

# Network performance testing
iperf3 -c speedtest.net -p 5201 -t 10
```

#### Alert Investigation
```bash
# Recent error investigation
journalctl --since "1 hour ago" --priority=err
grep -i error /var/lib/*/logs/vaultwarden/*.log | tail -20

# Performance issue analysis
./tools/monitor.sh --diagnostic --verbose
docker compose logs --since 1h | grep -i -E "error|warn|fail"
```

## Best Practices

### Monitoring Best Practices

#### Proactive Monitoring
- **Monitor trends** rather than just current values
- **Set appropriate thresholds** based on normal operational patterns
- **Test alert systems** regularly to ensure reliability
- **Document baseline performance** for comparison
- **Review monitoring data** weekly for pattern identification

#### Alert Management
- **Minimize false positives** by tuning alert thresholds
- **Prioritize alerts** by business impact and urgency
- **Document response procedures** for each alert type
- **Test recovery procedures** regularly
- **Maintain up-to-date contact information** for notifications

#### Performance Optimization
- **Monitor resource utilization** to identify optimization opportunities
- **Track database growth** and plan for capacity needs
- **Analyze access patterns** to optimize caching and performance
- **Monitor external dependencies** to identify bottlenecks
- **Regular performance baseline** updates as system evolves

This comprehensive monitoring system ensures proactive identification and resolution of issues while maintaining the "set and forget" operational philosophy of VaultWarden-OCI-Minimal.
