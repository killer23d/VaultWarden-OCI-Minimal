# OCI Vault Integration Guide

## Overview

VaultWarden-OCI-Minimal supports Oracle Cloud Infrastructure (OCI) Vault for enterprise-grade secret management. This integration provides centralized secret storage, access control, and audit logging while maintaining the system's "set and forget" philosophy with automatic fallback to local configuration.

## OCI Vault Benefits

### Enterprise Secret Management
- **Centralized Storage**: All secrets stored in OCI's secure vault service
- **Access Control**: Fine-grained IAM policies for secret access
- **Audit Logging**: Complete audit trail of secret access and modifications
- **Encryption**: Hardware Security Module (HSM) backed encryption
- **High Availability**: Multi-region replication and backup

### Operational Advantages
- **No Local Secrets**: Eliminates sensitive data stored on server filesystem
- **Dynamic Updates**: Change secrets without server access or restart
- **Team Management**: Multiple administrators with controlled access
- **Compliance**: Meets enterprise security and compliance requirements
- **Disaster Recovery**: Secrets survive complete server reconstruction

## Prerequisites

### OCI Account Setup
- **OCI Account**: Active Oracle Cloud Infrastructure account
- **Tenancy Access**: Administrator or appropriate IAM permissions
- **Compartment**: Dedicated compartment for VaultWarden resources
- **Vault Service**: OCI Vault service enabled in your region

### Required Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "vault:GetSecret",
        "vault:GetSecretBundle",
        "vault:ListSecrets",
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:oci:vault:*:*:secret/*",
        "arn:oci:kms:*:*:key/*"
      ]
    }
  ]
}
```

## OCI Vault Setup

### Step 1: Create Vault and Key

#### Create Master Encryption Key
```bash
# Using OCI CLI
oci kms management key create     --compartment-id <compartment-ocid>     --display-name "VaultWarden-Master-Key"     --key-shape '{"algorithm":"AES","length":256}'
```

#### Create Vault
```bash
# Create vault in your compartment
oci vault vault create     --compartment-id <compartment-ocid>     --display-name "VaultWarden-Secrets"     --vault-type DEFAULT
```

### Step 2: Create Secret in OCI Vault

#### Prepare Secret Content
```json
{
  "DOMAIN": "https://vault.example.com",
  "ADMIN_TOKEN": "generated-secure-admin-token",
  "ADMIN_EMAIL": "admin@example.com",
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_PORT": 587,
  "SMTP_SECURITY": "starttls",
  "SMTP_USERNAME": "vaultwarden@example.com",
  "SMTP_PASSWORD": "your-app-password",
  "SMTP_FROM": "noreply@example.com",
  "BACKUP_PASSPHRASE": "secure-backup-passphrase",
  "DATABASE_URL": "sqlite:///data/db.sqlite3",
  "CLOUDFLARE_EMAIL": "admin@example.com",
  "CLOUDFLARE_API_KEY": "your-cloudflare-api-key",
  "DDCLIENT_ENABLED": false,
  "SIGNUPS_ALLOWED": false,
  "WEBSOCKET_ENABLED": false
}
```

#### Create Secret
```bash
# Encode JSON as base64
echo '{"DOMAIN":"https://vault.example.com",...}' | base64 -w 0 > secret.b64

# Create secret in OCI Vault
oci vault secret create-secret     --compartment-id <compartment-ocid>     --secret-name "VaultWarden-Config"     --vault-id <vault-ocid>     --key-id <key-ocid>     --secret-content-content "$(cat secret.b64)"     --secret-content-content-type BASE64

# Clean up temporary file
rm secret.b64
```

### Step 3: Server Configuration

#### Install OCI CLI
```bash
# Download and install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Add to PATH (usually done automatically)
echo 'export PATH="$PATH:$HOME/bin"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
oci --version
```

#### Configure OCI CLI Authentication

##### Option 1: Instance Principal (Recommended for OCI Compute)
```bash
# Enable instance principal authentication
oci setup config --instance-principal

# Verify authentication works
oci iam region list
```

##### Option 2: API Key Authentication
```bash
# Interactive configuration
oci setup config

# Provide the following information:
# - User OCID
# - Tenancy OCID  
# - Region
# - Private key path
# - Public key fingerprint

# Test authentication
oci iam user get --user-id <your-user-ocid>
```

## Integration with VaultWarden

### Automated Setup

#### Run OCI Setup Script
```bash
# Navigate to project directory
cd /opt/VaultWarden-OCI-Minimal

# Run OCI Vault setup script
./tools/oci-setup.sh

# The script will:
# ✅ Verify OCI CLI configuration
# ✅ Test vault connectivity  
# ✅ Prompt for secret OCID
# ✅ Create systemd environment file
# ✅ Test configuration loading
# ✅ Backup existing local configuration
```

#### Interactive Setup Process
```bash
# During oci-setup.sh execution:
1. Enter OCI Secret OCID: ocid1.vaultsecret.oc1...
2. Choose whether to backup existing settings.json
3. Test secret retrieval and validation
4. Configure systemd service for OCI integration
```

### Manual Configuration

#### Set Environment Variable
```bash
# Create systemd environment file
sudo tee /etc/systemd/system/vaultwarden-oci-minimal.env << 'EOF'
OCI_SECRET_OCID=ocid1.vaultsecret.oc1.iad.xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

# Secure the environment file
sudo chmod 600 /etc/systemd/system/vaultwarden-oci-minimal.env
sudo chown root:root /etc/systemd/system/vaultwarden-oci-minimal.env

# Reload systemd configuration
sudo systemctl daemon-reload
```

#### Verify OCI Integration
```bash
# Test configuration loading
./startup.sh --validate

# Should show:
# ✅ OCI Vault configuration detected
# ✅ Secret retrieved successfully
# ✅ Configuration validated
```

## Secret Management Operations

### Retrieving Secrets

#### View Current Secret
```bash
# Get secret content (base64 encoded)
oci vault secret get-secret-bundle     --secret-id $OCI_SECRET_OCID     --query 'data."secret-bundle-content".content'     --raw-output

# Decode and view secret content
oci vault secret get-secret-bundle     --secret-id $OCI_SECRET_OCID     --query 'data."secret-bundle-content".content'     --raw-output | base64 -d | jq .
```

#### Test Secret Access
```bash
# Test secret access via VaultWarden scripts
export OCI_SECRET_OCID="ocid1.vaultsecret.oc1..."
source lib/config.sh
_load_configuration

# Should load configuration from OCI Vault
echo "Configuration source: $CONFIG_SOURCE"
```

### Updating Secrets

#### Upload Local Configuration to OCI Vault
```bash
# Use the update-secrets script
./tools/update-secrets.sh --upload-to-oci

# This will:
# ✅ Read current settings.json
# ✅ Validate JSON structure
# ✅ Create new secret version in OCI Vault
# ✅ Test retrieval of new version
# ✅ Update systemd configuration
```

#### Manual Secret Update
```bash
# Prepare new secret content
cat > new-secret.json << 'EOF'
{
  "DOMAIN": "https://vault.example.com",
  "ADMIN_TOKEN": "new-admin-token",
  "ADMIN_EMAIL": "admin@example.com"
}
EOF

# Encode as base64
base64 -w 0 new-secret.json > new-secret.b64

# Create new secret version
oci vault secret update-secret     --secret-id $OCI_SECRET_OCID     --secret-content-content "$(cat new-secret.b64)"     --secret-content-content-type BASE64

# Clean up temporary files
rm new-secret.json new-secret.b64

# Test new configuration
./startup.sh --validate
```

### Secret Versioning

#### List Secret Versions
```bash
# List all versions of the secret
oci vault secret list-secret-versions     --secret-id $OCI_SECRET_OCID

# Get specific version
oci vault secret get-secret-bundle     --secret-id $OCI_SECRET_OCID     --version-number 2
```

#### Rollback to Previous Version
```bash
# Get previous version content
PREVIOUS_CONTENT=$(oci vault secret get-secret-bundle     --secret-id $OCI_SECRET_OCID     --version-number 1     --query 'data."secret-bundle-content".content'     --raw-output)

# Create new version with previous content
oci vault secret update-secret     --secret-id $OCI_SECRET_OCID     --secret-content-content "$PREVIOUS_CONTENT"     --secret-content-content-type BASE64

# Restart services to load rollback configuration
./startup.sh
```

## Fallback Mechanism

### Automatic Fallback

The system implements robust fallback from OCI Vault to local configuration:

#### Fallback Triggers
- **OCI CLI Authentication Failure**: Invalid or expired credentials
- **Network Connectivity Issues**: Cannot reach OCI endpoints
- **Secret Access Errors**: Permission denied or secret not found
- **Secret Format Errors**: Invalid JSON or missing required keys
- **Service Timeouts**: OCI Vault service unavailable

#### Fallback Process
```bash
# The configuration loading follows this priority:
1. Check for OCI_SECRET_OCID environment variable
2. Attempt OCI Vault secret retrieval (3 retries with backoff)
3. On failure, log warning and fall back to local settings.json
4. Load and validate local configuration
5. Continue startup with local configuration
```

### Manual Fallback

#### Disable OCI Vault Temporarily
```bash
# Remove OCI environment variable
sudo rm /etc/systemd/system/vaultwarden-oci-minimal.env
sudo systemctl daemon-reload

# Restart with local configuration
./startup.sh

# Should show:
# ⚠️  No OCI Vault configuration found
# ✅ Loading configuration from local file
```

#### Re-enable OCI Vault
```bash
# Restore OCI environment
echo "OCI_SECRET_OCID=$YOUR_SECRET_OCID" | sudo tee /etc/systemd/system/vaultwarden-oci-minimal.env
sudo chmod 600 /etc/systemd/system/vaultwarden-oci-minimal.env
sudo systemctl daemon-reload

# Restart with OCI Vault
./startup.sh
```

## Monitoring and Troubleshooting

### OCI Vault Monitoring

#### Health Checks
```bash
# Check OCI authentication
oci iam region list

# Test secret access
oci vault secret get-secret-bundle --secret-id $OCI_SECRET_OCID --query 'data.id'

# Monitor configuration loading
./tools/monitor.sh --config-source

# Check logs for OCI-related issues
journalctl -t startup | grep -i oci
```

#### Common Issues and Solutions

##### Issue 1: Authentication Failures
```bash
# Symptoms: "Unable to authenticate with OCI"
# Solution: Verify OCI CLI configuration
oci setup config --repair

# For instance principal:
# Verify instance has proper IAM policy attached
```

##### Issue 2: Permission Denied
```bash
# Symptoms: "Access denied to secret"
# Solution: Verify IAM policies
oci iam policy list --compartment-id <compartment-ocid>

# Ensure user/instance has vault:GetSecret permission
```

##### Issue 3: Secret Not Found
```bash
# Symptoms: "Secret with OCID not found"  
# Solution: Verify secret OCID
oci vault secret list --compartment-id <compartment-ocid>

# Check secret is in correct compartment/region
```

##### Issue 4: Network Connectivity
```bash
# Symptoms: "Connection timeout" or "Unable to reach OCI endpoint"
# Solution: Check network connectivity
curl -I https://vault.oci.oraclecloud.com

# Verify DNS resolution
nslookup vault.oci.oraclecloud.com

# Check firewall/proxy settings
```

### Logging and Auditing

#### OCI Audit Logs
```bash
# View secret access logs in OCI Console:
# Navigation: Governance → Audit → Audit Logs
# Filter by:
# - Service: Vault
# - Resource Type: Secret
# - Action: GetSecret
```

#### Local Logging
```bash
# VaultWarden logs OCI operations
grep -i oci /var/lib/*/logs/vaultwarden/*.log

# System logs for configuration loading
journalctl -t startup | grep -i "config\|oci\|vault"

# Monitor configuration source
./tools/monitor.sh --verbose | grep -i "config source"
```

## Best Practices

### Security Best Practices

#### Access Control
- **Use Instance Principal**: Preferred for OCI Compute instances
- **Rotate API Keys**: Regular rotation of user API keys (if used)
- **Least Privilege**: Grant minimum required permissions
- **Compartment Isolation**: Dedicated compartment for VaultWarden resources

#### Secret Management
- **Regular Rotation**: Rotate secrets according to security policy
- **Version Control**: Use secret versioning for rollback capability
- **Backup Strategy**: Maintain backup copies of critical secrets
- **Audit Reviews**: Regular review of secret access logs

### Operational Best Practices

#### High Availability
- **Multi-Region**: Consider multi-region secret replication
- **Fallback Testing**: Regular testing of local fallback mechanism
- **Monitoring**: Monitor OCI Vault service health and connectivity
- **Documentation**: Maintain current OCI configuration documentation

#### Disaster Recovery
- **Secret Export**: Regular export of secrets for disaster recovery
- **Cross-Region Backup**: Backup secrets to different OCI region
- **Recovery Testing**: Test disaster recovery procedures quarterly
- **Access Procedures**: Document emergency secret access procedures

## Migration Scenarios

### Migrating to OCI Vault

#### From Local Configuration
```bash
# 1. Backup current configuration
cp settings.json settings.json.backup

# 2. Upload to OCI Vault
./tools/update-secrets.sh --upload-to-oci

# 3. Configure OCI integration
./tools/oci-setup.sh

# 4. Verify operation
./startup.sh --validate

# 5. Test fallback mechanism
sudo mv /etc/systemd/system/vaultwarden-oci-minimal.env /tmp/
./startup.sh --validate
sudo mv /tmp/vaultwarden-oci-minimal.env /etc/systemd/system/
```

### Migrating from OCI Vault

#### To Local Configuration
```bash
# 1. Download current secret
./tools/update-secrets.sh --download-from-oci

# 2. Verify local configuration
./startup.sh --validate

# 3. Disable OCI integration
sudo rm /etc/systemd/system/vaultwarden-oci-minimal.env
sudo systemctl daemon-reload

# 4. Test local operation
./startup.sh --validate
```

This OCI Vault integration provides enterprise-grade secret management while maintaining the system's simplicity and automated operation principles.
