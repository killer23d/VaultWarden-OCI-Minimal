# Cloudflare Integration Guide

## Overview

VaultWarden-OCI-Minimal is designed to work seamlessly with Cloudflare's proxy and security services. This integration provides DDoS protection, CDN acceleration, automatic SSL management, and enhanced security features while maintaining the "set and forget" philosophy.

## Cloudflare Setup

### DNS Configuration

#### Basic DNS Setup
1. **Add Domain to Cloudflare**
   - Sign up at cloudflare.com
   - Add your domain to Cloudflare
   - Update nameservers at your domain registrar

2. **Create DNS Records**
   ```
   Type: A
   Name: vault (or your chosen subdomain)
   Content: YOUR_SERVER_IP
   Proxy Status: Proxied (orange cloud icon)
   TTL: Auto
   ```

3. **Verify DNS Propagation**
   ```bash
   # Check DNS resolution
   dig vault.yourdomain.com
   nslookup vault.yourdomain.com

   # Verify Cloudflare proxy
   curl -I https://vault.yourdomain.com
   # Should show Cloudflare headers (CF-RAY, etc.)
   ```

### SSL/TLS Configuration

#### Recommended SSL Settings
```
SSL/TLS Mode: Full (strict)
Always Use HTTPS: On
Minimum TLS Version: 1.2
Automatic HTTPS Rewrites: On
Certificate Transparency Monitoring: On
```

#### Advanced SSL Options
```
Opportunistic Encryption: On
TLS 1.3: On
HSTS: Enabled (max-age=31536000; includeSubDomains)
Certificate Authority Authorization (CAA): Configured
```

### Security Configuration

#### Security Level Settings
```
Security Level: High
Challenge Passage: 30 minutes
Browser Integrity Check: On
Privacy Pass Support: On
```

#### Firewall Rules (Optional)
Create custom firewall rules for enhanced protection:
```javascript
// Block common attack patterns
(http.request.uri.path contains "wp-admin" or 
 http.request.uri.path contains ".php" or
 http.request.uri.path contains "admin" and not http.request.uri.path eq "/admin") and 
not cf.client_trust_score gt 30
```

## Automatic IP Management

### Cloudflare IP Updates

The system automatically maintains current Cloudflare IP ranges for security:

#### Automated Updates
- **Frequency**: Daily at 3:00 AM (via cron)
- **Script**: `./tools/update-cloudflare-ips.sh`
- **Configuration**: Updates `caddy/cloudflare-ips.caddy`
- **Reload**: Automatically reloads Caddy configuration

#### Manual IP Updates
```bash
# Update Cloudflare IP ranges manually
./tools/update-cloudflare-ips.sh

# Force update even if no changes detected
./tools/update-cloudflare-ips.sh --force

# Dry run to see what would be updated
./tools/update-cloudflare-ips.sh --dry-run

# Quiet mode for scripting
./tools/update-cloudflare-ips.sh --quiet
```

#### IP Range Validation
The system fetches and validates IP ranges from:
- **IPv4**: https://www.cloudflare.com/ips-v4
- **IPv6**: https://www.cloudflare.com/ips-v6

```bash
# Current IP ranges applied to Caddy
cat /etc/caddy-extra/cloudflare-ips.caddy

# Verify Caddy configuration
docker compose exec caddy caddy list-certificates
```

### Security Integration

#### Caddy Configuration
The system automatically restricts access to Cloudflare IPs only:
```caddy
vault.yourdomain.com {
    # Only allow Cloudflare IPs
    import /etc/caddy-extra/cloudflare-ips.caddy

    # Reverse proxy to VaultWarden
    reverse_proxy vaultwarden:8080

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
    }
}
```

## Fail2ban Integration

### Cloudflare API Configuration

#### Setup Cloudflare Credentials
Add to `settings.json`:
```json
{
  "CLOUDFLARE_EMAIL": "your-email@example.com",
  "CLOUDFLARE_API_KEY": "your-global-api-key"
}
```

#### Obtain Global API Key
1. Log in to Cloudflare dashboard
2. Go to My Profile → API Tokens
3. Copy Global API Key (or create a custom token)

#### Automatic Configuration
During `init-setup.sh`, the system will:
- Prompt for Cloudflare credentials
- Configure fail2ban actions
- Test API connectivity
- Enable Cloudflare banning

### Fail2ban Actions

#### Cloudflare Ban Action
When fail2ban detects malicious activity:
1. **Local Ban**: Add IP to local iptables (immediate effect)
2. **Cloudflare Ban**: Add IP to Cloudflare firewall (edge blocking)
3. **Notification**: Send alert email with details

#### Manual Cloudflare Management
```bash
# Check banned IPs at Cloudflare
fail2ban-client status cloudflare

# Manually ban IP at Cloudflare
fail2ban-client set cloudflare banip 1.2.3.4

# Unban IP from Cloudflare
fail2ban-client set cloudflare unbanip 1.2.3.4

# View Cloudflare ban log
tail -f /var/log/fail2ban.log | grep cloudflare
```

## Performance Optimization

### Cloudflare Caching

#### Recommended Cache Settings
```
Browser Cache TTL: 4 hours
Cache Level: Standard
Development Mode: Off
Auto Minify: CSS, HTML, JavaScript
Brotli Compression: On
```

#### Cache Rules
Create custom cache rules for VaultWarden:
```javascript
// Don't cache API endpoints
(http.request.uri.path starts_with "/api/" or
 http.request.uri.path starts_with "/admin" or
 http.request.uri.path starts_with "/identity")
Then: Bypass cache
```

### Performance Features

#### Speed Optimizations
```
Rocket Loader: Off (may interfere with VaultWarden)
Auto Minify HTML: On
Auto Minify CSS: On  
Auto Minify JS: On
Image Optimization: Lossless
```

#### Network Settings
```
HTTP/2: On
HTTP/3 (QUIC): On
0-RTT Connection Resumption: On
IPv6 Compatibility: On
WebSockets: On (required for VaultWarden)
```

## Advanced Configuration

### Custom Domain Setup

#### Multiple Domains
Configure multiple domains for the same VaultWarden instance:
```
Primary: vault.company.com
Alternate: passwords.company.com
Regional: vault-eu.company.com
```

Update Caddy configuration:
```caddy
vault.company.com, passwords.company.com, vault-eu.company.com {
    import /etc/caddy-extra/cloudflare-ips.caddy
    reverse_proxy vaultwarden:8080
}
```

### Access Policies

#### Cloudflare Access (Zero Trust)
For enhanced security, configure Cloudflare Access:

1. **Create Access Application**
   - Application Domain: vault.yourdomain.com
   - Application Type: Self-hosted

2. **Configure Identity Providers**
   - Google Workspace
   - Azure AD
   - GitHub
   - Email OTP

3. **Create Access Policies**
   ```
   Policy Name: VaultWarden Admin Access
   Action: Allow
   Include: Email addresses in list (admin@company.com)
   Require: Country is United States
   ```

### Geographic Restrictions

#### Country-Based Blocking
```javascript
// Block access from specific countries
ip.geoip.country in {"CN" "RU" "KP"}
Then: Block
```

#### Time-Based Access
```javascript
// Block access outside business hours
not (cf.edge.server_port eq 443 and 
     cf.edge.server_ip in {cloudflare_ips} and
     cf.timezone.hour ge 8 and cf.timezone.hour le 18)
Then: Challenge
```

## Monitoring and Analytics

### Cloudflare Analytics

#### Security Analytics
Monitor in Cloudflare dashboard:
- **Threat Analytics**: Blocked attacks, challenge solve rate
- **Bot Analytics**: Bot traffic patterns and blocking
- **Rate Limiting**: Request rate patterns and limits hit
- **Firewall Events**: Custom rule triggers and blocks

#### Performance Analytics
Track performance metrics:
- **Origin Performance**: Response times from your server
- **Cache Analytics**: Cache hit rates and bandwidth saved
- **Speed Analytics**: Page load times and Core Web Vitals
- **Reliability**: Uptime and error rate monitoring

### Custom Monitoring

#### Cloudflare API Monitoring
```bash
# Check Cloudflare API connectivity
curl -X GET "https://api.cloudflare.com/client/v4/user"      -H "X-Auth-Email: your-email@example.com"      -H "X-Auth-Key: your-api-key"

# Monitor DNS record status
curl -X GET "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records"      -H "X-Auth-Email: your-email@example.com"      -H "X-Auth-Key: your-api-key"
```

#### Integration with Monitoring Script
The monitoring script automatically checks:
- Cloudflare proxy status
- SSL certificate validity via Cloudflare
- DNS resolution through Cloudflare
- API rate limits and quotas

## Troubleshooting

### Common Issues

#### SSL/TLS Problems
```bash
# Check SSL certificate chain
openssl s_client -connect vault.yourdomain.com:443 -servername vault.yourdomain.com

# Verify Cloudflare SSL mode
curl -I https://vault.yourdomain.com
# Look for CF-Cache-Status and other Cloudflare headers

# Check origin certificate
docker compose exec caddy caddy list-certificates
```

#### DNS Resolution Issues
```bash
# Test direct server connection (bypass Cloudflare)
curl -H "Host: vault.yourdomain.com" http://YOUR_SERVER_IP

# Check Cloudflare DNS propagation
dig @8.8.8.8 vault.yourdomain.com
dig @1.1.1.1 vault.yourdomain.com

# Verify proxy status
dig vault.yourdomain.com
# Should return Cloudflare IP, not your server IP
```

#### IP Range Update Failures
```bash
# Check Cloudflare IP fetch
curl -s https://www.cloudflare.com/ips-v4
curl -s https://www.cloudflare.com/ips-v6

# Test IP update script
./tools/update-cloudflare-ips.sh --debug

# Manual IP range update
echo "remote_ip 173.245.48.0/20" > caddy/cloudflare-ips.caddy
docker compose exec caddy caddy reload
```

#### Fail2ban Cloudflare Integration Issues
```bash
# Test Cloudflare API credentials
fail2ban-client --test-cloudflare-api

# Check fail2ban Cloudflare action
fail2ban-client get cloudflare actions

# Manual test of Cloudflare banning
curl -X POST "https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules"      -H "X-Auth-Email: your-email@example.com"      -H "X-Auth-Key: your-api-key"      -H "Content-Type: application/json"      --data '{"mode":"block","configuration":{"target":"ip","value":"1.2.3.4"}}'
```

### Performance Issues

#### Slow Loading Times
1. **Check Cache Settings**: Ensure appropriate caching rules
2. **Verify Compression**: Enable Brotli and gzip compression
3. **Review Firewall Rules**: Overly restrictive rules can slow responses
4. **Monitor Origin**: Check server performance and response times

#### WebSocket Connection Problems
```bash
# Test WebSocket connectivity through Cloudflare
wscat -c wss://vault.yourdomain.com/notifications/hub

# Check Cloudflare WebSocket support
# Ensure WebSockets are enabled in Network settings

# Verify VaultWarden WebSocket configuration
grep WEBSOCKET settings.json
```

## Best Practices

### Security Best Practices

#### Defense in Depth
- **Use Cloudflare proxy** for all traffic (orange cloud)
- **Enable bot management** and challenge pages
- **Configure custom firewall rules** for known attack patterns
- **Monitor security events** regularly in analytics
- **Keep IP ranges updated** automatically

#### Access Control
- **Implement Cloudflare Access** for admin panel
- **Use geographic restrictions** if applicable
- **Configure rate limiting** for API endpoints
- **Enable audit logging** for all configuration changes

### Operational Best Practices

#### Monitoring
- **Set up alerts** for security events and performance issues
- **Review analytics weekly** for traffic patterns and threats
- **Monitor origin server health** through Cloudflare
- **Test failover procedures** regularly

#### Maintenance
- **Keep Cloudflare features updated** with new releases
- **Review and update firewall rules** quarterly
- **Test disaster recovery** with Cloudflare failover
- **Document configuration changes** and rationale

This Cloudflare integration provides enterprise-grade protection and performance for your VaultWarden deployment while maintaining simplicity and automation.
