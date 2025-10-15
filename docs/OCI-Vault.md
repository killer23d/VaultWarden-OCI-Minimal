# OCI Vault Integration Guide

> **🎯 Enterprise Secret Management**: Seamlessly integrate Oracle Cloud Infrastructure (OCI) Vault for centralized, secure secret management with automatic fallback to local configuration.

## 🏗️ **OCI Vault Architecture Overview**

VaultWarden-OCI-Minimal provides **hybrid secret management** that combines the security of enterprise-grade OCI Vault with the reliability of local configuration fallback:

```bash
Secret Management Architecture:
├── Primary: OCI Vault (Cloud-based HSM-backed secrets)
├── Fallback: Local settings.json (Encrypted local storage)
├── Runtime: In-memory only (Secrets never persist on disk)
├── Authentication: OCI CLI integration + Service Principal
├── Encryption: AES-256 with HSM backing (OCI Vault)
└── Audit: Complete access logging and compliance tracking
```

### **Benefits of OCI Vault Integration**

#### **Security Advantages**
```bash
Enterprise Security Features:
├── Hardware Security Module (HSM) backing
├── Centralized secret rotation and lifecycle management
├── Fine-grained access controls and IAM integration
├── Complete audit logging for compliance
├── Encryption key management by Oracle Cloud
├── Geographic replication and disaster recovery
└── Zero-trust architecture compatible
```

#### **Operational Advantages**
```bash
Operational Benefits:
├── Centralized secret management across environments
├── Automatic secret rotation capabilities
├── Integration with existing OCI infrastructure
├── Compliance with enterprise security policies
├── Reduced local secret storage requirements
├── Automated backup and recovery of secrets
└── Seamless scaling across multiple deployments
```

## 🚀 **OCI Vault Setup and Configuration**

### **Prerequisites**

#### **OCI Account Requirements**
```bash
Required OCI Resources:
├── OCI Account with sufficient permissions
├── Compartment for VaultWarden resources
├── OCI Vault instance (or create new)
├── Encryption key (AES-256 recommended)
├── Secret storage capability
└── API access credentials configured

Required Permissions:
├── manage vaults (compartment)
├── manage keys (compartment)
├── manage secrets (compartment)
├── read secret-bundles (compartment)
└── inspect compartments (tenancy)
```

#### **Local System Requirements**
```bash
# OCI CLI must be installed and configured
# Installation (Ubuntu 24.04):
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Verify installation
oci --version
# Expected: oci-cli version 3.x.x or higher

# Test authentication
oci iam region list
# Should return list of OCI regions without errors
```

### **OCI Vault Resource Creation**

#### **Create Vault and Key (OCI Console Method)**
```bash
# Via OCI Web Console:
# 1. Navigate to Security > Vault
# 2. Create Vault:
#    - Name: vaultwarden-secrets
#    - Compartment: Select appropriate compartment
#    - Vault Type: Default (recommended)
# 
# 3. Create Master Key:
#    - Name: vaultwarden-master-key
#    - Protection Mode: HSM (recommended) or Software
#    - Algorithm: AES-256
#    - Key Usage: Encrypt/Decrypt
#
# 4. Note the OCIDs:
#    - Vault OCID: ocid1.vault.oc1.region.xxx
#    - Key OCID: ocid1.key.oc1.region.xxx
```

#### **Create Secret (Manual Method)**
```bash
# Create secret in OCI Console:
# 1. Navigate to your Vault > Secrets
# 2. Create Secret:
#    - Name: vaultwarden-config
#    - Description: VaultWarden configuration secrets
#    - Encryption Key: Select your master key
#    - Secret Type: Base64
#    - Secret Contents: Upload/paste your configuration JSON

# Example secret content (base64 encode your settings.json):
base64 -w 0 settings.json
# Copy the output and paste as secret content

# Note the Secret OCID: ocid1.vaultsecret.oc1.region.xxx
```

### **Automated OCI Vault Setup**

#### **Using the OCI Setup Script**
```bash
# Run the OCI setup wizard
./tools/oci-setup.sh

# Interactive setup process:
🔐 VaultWarden-OCI-Minimal OCI Vault Setup

Prerequisites Check:
✅ OCI CLI installed and configured
✅ Authentication successful
✅ Required permissions verified
✅ Existing settings.json found

Setup Options:
[1] Upload existing configuration to new OCI Vault secret
[2] Connect to existing OCI Vault secret
[3] Create new vault, key, and secret (full setup)
[4] Test existing OCI Vault connection

Select setup option [1-4]: 1

📤 Uploading Configuration to OCI Vault

Available compartments:
[1] root-compartment (ocid1.compartment.oc1..xxx)
[2] vaultwarden-compartment (ocid1.compartment.oc1..xxx)
[3] production-compartment (ocid1.compartment.oc1..xxx)

Select compartment [1-3]: 2

Available vaults in compartment:
[1] vaultwarden-secrets (ocid1.vault.oc1..xxx) - Active
[2] general-secrets (ocid1.vault.oc1..xxx) - Active

Select vault [1-2]: 1

Available keys in vault:
[1] vaultwarden-master-key (ocid1.key.oc1..xxx) - Enabled
[2] backup-key (ocid1.key.oc1..xxx) - Enabled

Select encryption key [1-2]: 1

Secret Configuration:
Name: vaultwarden-config-prod
Description: VaultWarden production configuration
Base64 encoding: Automatic

🔐 Creating secret...
✅ Configuration uploaded successfully
✅ Secret created with OCID: ocid1.vaultsecret.oc1.region.abcdef...

🔧 Configuring local integration...
✅ Systemd environment file created
✅ Environment variable configured
✅ Automatic fallback enabled

🎯 OCI Vault setup completed successfully!

Configuration Summary:
- Secret OCID: ocid1.vaultsecret.oc1.region.abcdef...
- Vault Name: vaultwarden-secrets
- Compartment: vaultwarden-compartment  
- Encryption: AES-256 with HSM backing
- Fallback: Local settings.json (automatic)

Next Steps:
1. Test configuration: ./startup.sh --validate
2. Start services: ./startup.sh
3. Backup secret OCID securely
4. Remove local settings.json (optional)
```

#### **Manual OCI Secret Creation**
```bash
# Create secret using OCI CLI (alternative method)
COMPARTMENT_OCID="ocid1.compartment.oc1..xxx"
VAULT_OCID="ocid1.vault.oc1.region.xxx"
KEY_OCID="ocid1.key.oc1.region.xxx"

# Encode configuration
CONFIG_B64=$(base64 -w 0 settings.json)

# Create secret
oci vault secret create-secret \
    --compartment-id "$COMPARTMENT_OCID" \
    --vault-id "$VAULT_OCID" \
    --key-id "$KEY_OCID" \
    --secret-name "vaultwarden-config-$(date +%Y%m%d)" \
    --description "VaultWarden configuration secrets" \
    --secret-content-content "$CONFIG_B64" \
    --secret-content-content-type "BASE64"

# Note the returned secret OCID for configuration
```

### **Local Integration Configuration**

#### **Environment Configuration**
```bash
# The setup script creates systemd environment file
# Location: /etc/systemd/system/vaultwarden-oci-minimal.env

cat /etc/systemd/system/vaultwarden-oci-minimal.env
# Contents:
# VaultWarden-OCI-Minimal Environment Configuration
# Generated: 2024-10-14T17:30:25Z
# Source: OCI Vault Integration Setup
OCI_SECRET_OCID=ocid1.vaultsecret.oc1.region.abcdef...

# Verify environment loading
source /etc/systemd/system/vaultwarden-oci-minimal.env
echo $OCI_SECRET_OCID
# Should output the secret OCID
```

#### **Systemd Service Integration**
```bash
# Systemd service file is automatically created/updated
cat /etc/systemd/system/vaultwarden-oci-minimal.service

# Key sections for OCI integration:
[Unit]
Description=VaultWarden-OCI-Minimal Stack
Documentation=https://github.com/killer23d/VaultWarden-OCI-Minimal
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

# OCI Environment Integration
EnvironmentFile=-/etc/systemd/system/vaultwarden-oci-minimal.env
WorkingDirectory=/opt/VaultWarden-OCI-Minimal
Environment=COMPOSE_PROJECT_NAME=vaultwarden-oci-minimal

# Execution
ExecStart=/opt/VaultWarden-OCI-Minimal/startup.sh
ExecStop=/usr/bin/docker compose -f /opt/VaultWarden-OCI-Minimal/docker-compose.yml down
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target

# Enable and start service
systemctl daemon-reload
systemctl enable vaultwarden-oci-minimal.service
systemctl start vaultwarden-oci-minimal.service
```

## 🔄 **Configuration Loading Process**

### **Hybrid Configuration System**

#### **Configuration Loading Priority**
```bash
Configuration Loading Order (First Available Wins):
1. OCI Vault Secret (if OCI_SECRET_OCID environment variable set)
   └── Validates OCI CLI authentication
   └── Fetches secret from OCI Vault
   └── Decodes base64 content
   └── Parses and validates JSON

2. Local settings.json (fallback if OCI unavailable)
   └── Validates file existence and permissions
   └── Parses and validates JSON content
   └── Applies security checks

3. Interactive Prompts (if neither source available)
   └── Prompts for essential configuration
   └── Creates temporary configuration
   └── Suggests running setup scripts
```

#### **Configuration Loading Verification**
```bash
# Test configuration loading process
./startup.sh --validate

# Expected output with OCI Vault:
🔍 VaultWarden-OCI-Minimal Configuration Validation

Configuration Source Detection:
✅ OCI_SECRET_OCID environment variable found
✅ OCI CLI authentication successful
✅ OCI Vault connectivity verified

Configuration Loading:
📡 Loading from OCI Vault: ocid1.vaultsecret.oc1.region.abcdef...
✅ Secret retrieved successfully (842 bytes)
✅ Base64 decoding successful  
✅ JSON parsing successful
✅ Configuration validation passed

Configuration Summary:
- Source: OCI Vault (vaultwarden-secrets)
- Keys loaded: 28 configuration items
- Domain: https://vault.yourdomain.com
- Security: All sensitive values loaded securely

Fallback Configuration:
✅ Local settings.json exists and valid (backup available)
✅ Automatic fallback configured

🎯 Configuration validation completed successfully
```

#### **Fallback Mechanism Testing**
```bash
# Test fallback to local configuration
# Temporarily disable OCI access
unset OCI_SECRET_OCID
./startup.sh --validate

# Expected fallback behavior:
🔍 Configuration Source Detection:
⚠️  OCI_SECRET_OCID not found in environment
📂 Falling back to local configuration

Configuration Loading:
📄 Loading from local file: settings.json
✅ File exists and readable (600 permissions)
✅ JSON parsing successful
✅ Configuration validation passed

Configuration Summary:
- Source: Local File (settings.json)
- Keys loaded: 28 configuration items
- Domain: https://vault.yourdomain.com
- Security: File permissions secure

🔧 Automatic fallback successful
✅ System operational with local configuration
```

### **Runtime Secret Management**

#### **In-Memory Secret Handling**
```bash
# Secrets are loaded into environment variables at runtime
# Never written to disk when using OCI Vault

Configuration Security Features:
├── In-Memory Only: Secrets loaded directly to environment
├── Process Isolation: Each container has separate environment
├── No Disk Persistence: OCI secrets never stored locally
├── Automatic Cleanup: Environment cleared on process termination
├── Audit Trail: All OCI access logged automatically
└── Encryption in Transit: TLS for all OCI API communications
```

#### **Secret Rotation Workflow**
```bash
# Update secrets in OCI Vault (zero-downtime rotation)

# 1. Create new version of secret in OCI Vault
oci vault secret update-secret \
    --secret-id "$OCI_SECRET_OCID" \
    --secret-content-content "$(base64 -w 0 new-settings.json)" \
    --secret-content-content-type "BASE64"

# 2. Restart VaultWarden to load new configuration
systemctl restart vaultwarden-oci-minimal

# 3. Verify new configuration loaded
./startup.sh --validate

# 4. Test service functionality
curl -I https://your-domain.com
```

## 🔧 **Management and Operations**

### **OCI Vault Monitoring**

#### **Connection Health Monitoring**
```bash
# OCI Vault connectivity is monitored automatically
# Monitoring script checks every 5 minutes via cron

# Manual connection test
./tools/monitor.sh --oci-vault-check

# Expected output:
🔐 OCI Vault Health Check

Connection Test:
✅ OCI CLI authentication active
✅ Network connectivity to OCI services
✅ API rate limits within acceptable range

Secret Access Test:
✅ Secret OCID accessible: ocid1.vaultsecret.oc1.region.abcdef...
✅ Secret retrieval successful (842 bytes)
✅ Base64 decoding successful
✅ Configuration parsing successful

Performance Metrics:
📊 Secret retrieval time: 247ms
📊 Authentication time: 89ms
📊 Total request time: 336ms

Security Verification:
✅ TLS encryption active for all requests
✅ Audit logging enabled
✅ Access permissions verified

Status: 🟢 OCI Vault fully operational
```

#### **Fallback Monitoring**
```bash
# Monitor fallback configuration status
./tools/monitor.sh --fallback-status

# Configuration resilience check
🔄 Configuration Resilience Status

Primary Configuration (OCI Vault):
✅ Available and responding
✅ Last successful access: 2 minutes ago
✅ Response time: 247ms (good)

Fallback Configuration (Local):
✅ settings.json exists and valid
✅ File permissions: 600 (secure)
✅ Last modified: 3 days ago
✅ Content verification: passed

Resilience Test:
✅ Primary → Fallback transition: < 5 seconds
✅ Fallback → Primary recovery: < 10 seconds
✅ No configuration drift detected
✅ Both sources contain identical essential config

Status: 🟢 Configuration system highly resilient
```

### **Secret Lifecycle Management**

#### **Secret Versioning and History**
```bash
# OCI Vault maintains secret version history automatically
# View secret version history

oci vault secret list-secret-versions \
    --secret-id "$OCI_SECRET_OCID" \
    --query 'data[].{Version:version-number,Status:stage,Created:time-created}' \
    --output table

# Example output:
Version    Status     Created
-------    ------     -------
3          CURRENT    2024-10-14T17:30:25.123Z
2          PREVIOUS   2024-10-07T09:15:42.567Z  
1          PREVIOUS   2024-09-30T14:22:18.890Z

# Rollback to previous version if needed
oci vault secret update-secret \
    --secret-id "$OCI_SECRET_OCID" \
    --current-version-number 2
```

#### **Configuration Synchronization**
```bash
# Sync local configuration to OCI Vault
./tools/update-secrets.sh --sync-to-oci

# Sync OCI Vault configuration to local file (backup)
./tools/update-secrets.sh --sync-from-oci

# Compare configurations for drift detection
./tools/update-secrets.sh --compare-sources

# Expected comparison output:
🔍 Configuration Source Comparison

Comparing OCI Vault vs Local settings.json:

Identical Keys (25):
✅ DOMAIN, ADMIN_EMAIL, SMTP_HOST, DATABASE_URL...

Different Values (2):
⚠️  ADMIN_TOKEN: Values differ (recommend OCI version)
⚠️  BACKUP_PASSPHRASE: Values differ (recommend OCI version)

OCI Vault Only (1):
🆕 CLOUDFLARE_API_KEY: Present in OCI, missing in local

Local File Only (0):
   (None)

Recommendations:
1. Update local file with OCI values for consistency
2. Consider removing CLOUDFLARE_API_KEY from local file
3. Run sync operation to resolve differences

Action: ./tools/update-secrets.sh --sync-from-oci --backup-first
```

### **Backup and Recovery Integration**

#### **OCI Vault and Backup Strategy**
```bash
# Backup strategy with OCI Vault integration

Backup Components with OCI Vault:
├── Configuration Backup:
│   ├── OCI Vault secret OCID (essential for recovery)
│   ├── OCI authentication configuration
│   ├── Local settings.json (fallback backup)
│   └── Environment files and systemd configuration
├── Data Backup:
│   ├── VaultWarden database (encrypted)
│   ├── SSL certificates and keys
│   ├── Application logs and state
│   └── Docker volumes and container data
└── Recovery Information:
    ├── OCI Vault access procedures
    ├── Service principal credentials (secure storage)
    ├── Compartment and vault OCIDs
    └── Emergency recovery procedures
```

#### **Disaster Recovery with OCI Vault**
```bash
# Complete disaster recovery procedure

# Scenario: Complete server loss, OCI Vault data intact
# Recovery Steps:

# 1. New server setup
# Deploy new Ubuntu 24.04 server
# Install VaultWarden-OCI-Minimal

# 2. OCI CLI configuration
oci setup config
# Configure with same tenancy/user/key

# 3. Environment restoration
echo "OCI_SECRET_OCID=ocid1.vaultsecret.oc1.region.abcdef..." > /etc/systemd/system/vaultwarden-oci-minimal.env

# 4. Test OCI Vault connectivity
./startup.sh --validate

# 5. Data restoration (if backup available)
./tools/restore.sh /path/to/data/backup

# 6. Service startup
systemctl enable vaultwarden-oci-minimal
systemctl start vaultwarden-oci-minimal

# Result: Full recovery with all configuration from OCI Vault
```

### **Security and Compliance**

#### **Audit Logging**
```bash
# OCI Vault provides comprehensive audit logs
# Access via OCI Console: Governance > Audit

# Common audit events to monitor:
# - Secret access (read operations)
# - Secret modifications (update operations)  
# - Authentication events
# - Permission changes
# - API rate limiting events

# Query audit logs via OCI CLI
oci audit event list \
    --compartment-id "$COMPARTMENT_OCID" \
    --start-time "2024-10-14T00:00:00Z" \
    --end-time "2024-10-14T23:59:59Z" \
    --query 'data[?contains(event-name, `secret`)]'
```

#### **Access Control and Permissions**
```bash
# Implement least privilege access for OCI Vault

# Service Principal Permissions (recommended minimum):
allow group vaultwarden-service to read secret-bundles in compartment vaultwarden
allow group vaultwarden-service to inspect vaults in compartment vaultwarden
allow group vaultwarden-service to inspect keys in compartment vaultwarden

# Human Administrator Permissions:
allow group vaultwarden-admins to manage secrets in compartment vaultwarden
allow group vaultwarden-admins to manage vaults in compartment vaultwarden
allow group vaultwarden-admins to manage keys in compartment vaultwarden

# Emergency Break-Glass Permissions:
allow group emergency-access to read all-resources in compartment vaultwarden

# Verify current permissions
oci iam policy list --compartment-id "$COMPARTMENT_OCID" \
    --query 'data[?contains(name, `vaultwarden`)]'
```

## 🛠️ **Troubleshooting OCI Vault Integration**

### **Common Issues and Solutions**

#### **Authentication Issues**
```bash
# Issue: OCI CLI authentication failures
# Symptoms: "Authentication failed" or "Invalid credentials"

# Diagnostic steps:
# 1. Test basic OCI connectivity
oci iam region list

# 2. Verify OCI configuration
cat ~/.oci/config

# 3. Check key file permissions
ls -la ~/.oci/
# Private key should be 600 permissions

# 4. Test with different profile (if multiple exist)
oci iam region list --profile alternative-profile

# 5. Regenerate OCI CLI configuration if needed
oci setup config
```

#### **Secret Access Issues**
```bash
# Issue: Cannot access OCI Vault secret
# Symptoms: "Secret not found" or "Access denied"

# Diagnostic steps:
# 1. Verify secret OCID
oci vault secret get --secret-id "$OCI_SECRET_OCID"

# 2. Check compartment access
oci iam compartment get --compartment-id "$COMPARTMENT_OCID"

# 3. Test secret bundle access
oci vault secret get-secret-bundle --secret-id "$OCI_SECRET_OCID" --stage CURRENT

# 4. Verify permissions
oci iam policy list --compartment-id "$COMPARTMENT_OCID"

# 5. Check audit logs for access attempts
oci audit event list --compartment-id "$COMPARTMENT_OCID" --start-time "$(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ)"
```

#### **Performance Issues**
```bash
# Issue: Slow OCI Vault response times
# Symptoms: Long startup times, timeouts

# Diagnostic and optimization:
# 1. Test network connectivity to OCI
time oci iam region list

# 2. Check OCI service health
curl -I https://vault.us-ashburn-1.oraclecloud.com

# 3. Monitor response times
./tools/monitor.sh --oci-performance

# 4. Implement caching (if appropriate)
# Note: Be cautious with caching secrets for security reasons

# 5. Optimize retry configuration
# Edit ~/.oci/config:
[DEFAULT]
region = us-ashburn-1
user = ocid1.user.oc1..xxx
fingerprint = xx:xx:xx...
key_file = ~/.oci/oci_api_key.pem
tenancy = ocid1.tenancy.oc1..xxx
max_retries = 3
retry_strategy = exponential_backoff
```

#### **Fallback Activation Issues**
```bash
# Issue: Fallback not activating when OCI unavailable
# Symptoms: Service fails instead of using local config

# Troubleshooting steps:
# 1. Verify fallback configuration exists
ls -la settings.json

# 2. Test manual fallback activation
unset OCI_SECRET_OCID
./startup.sh --validate

# 3. Check fallback logic in config loading
source lib/config.sh
_load_configuration

# 4. Verify environment variable handling
echo $OCI_SECRET_OCID

# 5. Test with debug mode
DEBUG=1 ./startup.sh
```

### **Emergency Recovery Procedures**

#### **Complete OCI Access Loss**
```bash
# Emergency procedure if OCI Vault becomes inaccessible

# 1. Immediate service continuity (use local fallback)
unset OCI_SECRET_OCID
systemctl restart vaultwarden-oci-minimal

# 2. Verify service operation with local config
./startup.sh --validate

# 3. Create backup of current local configuration
cp settings.json settings.json.emergency-backup-$(date +%Y%m%d-%H%M%S)

# 4. Document the incident
echo "$(date): OCI Vault access lost, switched to local fallback" >> /var/log/vaultwarden-incidents.log

# 5. Investigate OCI access restoration
# Check OCI service health, network connectivity, authentication
```

#### **Secret Corruption or Loss**
```bash
# Emergency procedure if OCI Vault secret is corrupted/deleted

# 1. Immediate assessment
oci vault secret get --secret-id "$OCI_SECRET_OCID" || echo "Secret inaccessible"

# 2. Check for secret versions/backups
oci vault secret list-secret-versions --secret-id "$OCI_SECRET_OCID"

# 3. Restore from local backup if available
if [ -f settings.json ]; then
    echo "Local backup available, can continue operations"
    unset OCI_SECRET_OCID
    systemctl restart vaultwarden-oci-minimal
fi

# 4. Recreate secret from local configuration
if [ -f settings.json ]; then
    ./tools/update-secrets.sh --recreate-oci-secret
fi

# 5. Update environment with new secret OCID
echo "OCI_SECRET_OCID=new-secret-ocid" > /etc/systemd/system/vaultwarden-oci-minimal.env
systemctl daemon-reload
systemctl restart vaultwarden-oci-minimal
```

## 📚 **Best Practices and Recommendations**

### **Security Best Practices**

#### **OCI Vault Security Hardening**
```bash
Security Hardening Checklist:

Access Control:
- [ ] Use dedicated service principal (not user credentials)
- [ ] Implement least privilege permissions
- [ ] Regular access review and rotation
- [ ] Enable MFA for human administrator access

Secret Management:
- [ ] Regular secret rotation (quarterly recommended)
- [ ] Monitor secret access via audit logs
- [ ] Maintain local backup for emergency fallback
- [ ] Use separate secrets for different environments

Network Security:
- [ ] Restrict OCI API access to known IP ranges (if possible)
- [ ] Use VPN/private connectivity for sensitive environments
- [ ] Monitor for unusual API access patterns
- [ ] Enable OCI Web Application Firewall if applicable

Compliance:
- [ ] Configure audit log retention per compliance requirements
- [ ] Document secret access procedures
- [ ] Regular compliance audits and reviews
- [ ] Incident response procedures documented
```

#### **Operational Best Practices**
```bash
Operational Excellence:

Monitoring:
- [ ] Set up OCI Vault health monitoring
- [ ] Monitor secret access patterns
- [ ] Alert on authentication failures
- [ ] Track configuration drift

Backup and Recovery:
- [ ] Test fallback mechanisms regularly
- [ ] Maintain emergency recovery procedures
- [ ] Document all OCIDs and access information
- [ ] Practice disaster recovery scenarios

Change Management:
- [ ] Use version control for secret changes
- [ ] Test configuration changes in non-production
- [ ] Document all secret modifications
- [ ] Coordinate secret rotations with maintenance windows
```

This comprehensive OCI Vault integration provides enterprise-grade secret management while maintaining the simplicity and reliability that makes VaultWarden-OCI-Minimal ideal for small teams."""
