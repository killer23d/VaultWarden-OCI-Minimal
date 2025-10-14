#!/usr/bin/env bash
# lib/config.sh - Configuration management with OCI Vault and systemd support
# Part of VaultWarden OCI Minimal stack
#
# This library provides centralized configuration management with support for:
# - Local settings.json files
# - OCI Vault integration for cloud deployments  
# - Systemd environment file management
# - Automatic service name and path detection
#
# Dependencies: lib/logging.sh, lib/validation.sh
# Author: VaultWarden OCI Minimal Project
# License: MIT
#

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# --- FIX: Centralized project path and URL detection ---
PROJECT_NAME="$(basename "$ROOT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
SERVICE_NAME="${PROJECT_NAME}.service"
# NOTE: The /var/lib path is a standard for Linux/Ubuntu.
# For other OSes, this variable may need to be adjusted.
PROJECT_STATE_DIR="/var/lib/${PROJECT_NAME}"
CONFIG_BACKUP_DIR="${PROJECT_STATE_DIR}/config-backups"
SYSTEMD_ENV_FILE="/etc/systemd/system/${PROJECT_NAME}.env"

_get_project_url() {
    if [[ -d "$ROOT_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
        local remote_url
        remote_url=$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            # Remove .git suffix if present
            echo "${remote_url%.git}"
            return 0
        fi
    fi
    # Fallback if not a git repo or remote is not set
    echo "https://github.com/your-username/your-forked-repo"
}
PROJECT_URL="$(_get_project_url)"
# --- END FIX ---

# Source required libraries
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/validation.sh"

# Configuration constants
readonly CONFIG_FILE="$ROOT_DIR/settings.json"

# Global configuration variables (populated by load functions)
declare -gA CONFIG_VALUES=()
declare -g CONFIG_LOADED=false
declare -g CONFIG_SOURCE=""

# Initialize configuration system
_init_config_system() {
    if [[ ! -d "$CONFIG_BACKUP_DIR" ]]; then
        mkdir -p "$CONFIG_BACKUP_DIR"
        chmod 700 "$CONFIG_BACKUP_DIR"
    fi
}

# Load systemd environment file if it exists
_load_systemd_environment() {
    if [[ -f "$SYSTEMD_ENV_FILE" ]] && [[ -z "${OCI_SECRET_OCID:-}" ]]; then
        _log_debug "Loading systemd environment from $SYSTEMD_ENV_FILE"
        
        local file_perms
        file_perms=$(stat -c "%a" "$SYSTEMD_ENV_FILE")
        if [[ "$file_perms" != "600" ]]; then
            _log_warning "Insecure permissions on $SYSTEMD_ENV_FILE (should be 600)"
        fi
        
        set -a
        source "$SYSTEMD_ENV_FILE"
        set +a
        
        _log_debug "Systemd environment loaded successfully"
    fi
}

# Validate OCI CLI configuration and connectivity
_validate_oci_environment() {
    if ! command -v oci >/dev/null 2>&1; then
        _log_error "OCI CLI not installed"
        return 1
    fi
    
    if ! oci iam region list >/dev/null 2>&1; then
        _log_error "OCI CLI authentication failed"
        return 1
    fi
    
    local required_vars=("OCI_SECRET_OCID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            _log_error "Required OCI environment variable not set: $var"
            return 1
        fi
    done
    
    return 0
}

# Load configuration from OCI Vault
_load_from_oci_vault() {
    _log_info "Loading configuration from OCI Vault..."
    
    if ! _validate_oci_environment; then
        _log_error "OCI environment validation failed"
        return 1
    fi
    
    local secret_content
    local max_retries=3
    local retry_delay=2
    
    for ((i=1; i<=max_retries; i++)); do
        _log_debug "Attempting to fetch secret (attempt $i/$max_retries)"
        
        if secret_content=$(oci vault secret get-secret-bundle \
            --secret-id "$OCI_SECRET_OCID" \
            --query 'data."secret-bundle-content".content' \
            --raw-output 2>/dev/null); then
            
            break
        else
            if [[ $i -eq $max_retries ]]; then
                _log_error "Failed to fetch secret after $max_retries attempts"
                return 1
            fi
            
            _log_warning "Failed to fetch secret, retrying in ${retry_delay}s..."
            sleep $retry_delay
        fi
    done
    
    local decoded_content
    if ! decoded_content=$(echo "$secret_content" | base64 -d); then
        _log_error "Failed to decode secret content"
        return 1
    fi
    
    if ! echo "$decoded_content" | jq . >/dev/null 2>&1; then
        _log_error "Secret content is not valid JSON"
        return 1
    fi
    
    if ! _parse_json_config "$decoded_content"; then
        _log_error "Failed to parse OCI vault configuration"
        return 1
    fi
    
    CONFIG_SOURCE="oci_vault"
    CONFIG_LOADED=true
    
    _log_success "Configuration loaded from OCI Vault (OCID: ${OCI_SECRET_OCID:0:20}...)"
    return 0
}

# Load configuration from local settings.json file
_load_from_local_file() {
    _log_info "Loading configuration from local file..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        _log_error "Configuration file not found: $CONFIG_FILE"
        _log_info "Run ./tools/init-setup.sh to create initial configuration"
        return 1
    fi
    
    local file_perms
    file_perms=$(stat -c "%a" "$CONFIG_FILE")
    if [[ "$file_perms" != "600" ]]; then
        _log_warning "Insecure permissions on $CONFIG_FILE (should be 600)"
        chmod 600 "$CONFIG_FILE"
    fi
    
    if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        _log_error "Configuration file contains invalid JSON"
        return 1
    fi
    
    if ! _parse_json_config "$(cat "$CONFIG_FILE")"; then
        _log_error "Failed to parse local configuration file"
        return 1
    fi
    
    CONFIG_SOURCE="local_file"
    CONFIG_LOADED=true
    
    _log_success "Configuration loaded from local file"
    return 0
}

# Parse JSON configuration into CONFIG_VALUES associative array
_parse_json_config() {
    local json_content="$1"
    
    local required_keys=(
        "DOMAIN"
        "ADMIN_TOKEN"
        "SMTP_HOST"
        "SMTP_FROM"
        "SMTP_USERNAME"
        "SMTP_PASSWORD"
        "DATABASE_URL"
        "BACKUP_PASSPHRASE"
    )
    
    CONFIG_VALUES=()
    
    local keys
    keys=$(echo "$json_content" | jq -r 'keys[]' 2>/dev/null)
    
    if [[ -z "$keys" ]]; then
        _log_error "No configuration keys found in JSON"
        return 1
    fi
    
    while IFS= read -r key; do
        local value
        value=$(echo "$json_content" | jq -r --arg key "$key" '.[$key]' 2>/dev/null)
        
        if [[ "$value" != "null" ]]; then
            CONFIG_VALUES["$key"]="$value"
            _log_debug "Loaded config key: $key"
        fi
    done <<< "$keys"
    
    for key in "${required_keys[@]}"; do
        if [[ -z "${CONFIG_VALUES[$key]:-}" ]]; then
            _log_error "Required configuration key missing: $key"
            return 1
        fi
    done
    
    if [[ -n "${CONFIG_VALUES[APP_DOMAIN]:-}" ]] && [[ -z "${CONFIG_VALUES[DOMAIN]:-}" ]]; then
        _log_warning "Converting legacy APP_DOMAIN to DOMAIN"
        CONFIG_VALUES["DOMAIN"]="https://${CONFIG_VALUES[APP_DOMAIN]}"
        _log_info "Set DOMAIN to: ${CONFIG_VALUES[DOMAIN]}"
    fi
    
    if [[ -n "${CONFIG_VALUES[DOMAIN]:-}" ]]; then
        local domain="${CONFIG_VALUES[DOMAIN]}"
        domain="${domain%/}"
        if [[ ! "$domain" =~ ^https?:// ]] && [[ "$domain" =~ [a-zA-Z0-9.-]+\.[a-zA-Z]{2,} ]]; then
            domain="https://$domain"
            _log_debug "Added https:// prefix to DOMAIN: $domain"
        fi
        CONFIG_VALUES["DOMAIN"]="$domain"
    fi
    
    _log_debug "Parsed ${#CONFIG_VALUES[@]} configuration keys"
    return 0
}

# Export configuration as environment variables for docker-compose
_export_configuration() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        _log_error "Configuration not loaded. Call _load_configuration first."
        return 1
    fi
    
    _log_debug "Exporting configuration as environment variables..."
    
    for key in "${!CONFIG_VALUES[@]}"; do
        export "$key=${CONFIG_VALUES[$key]}"
        _log_debug "Exported: $key"
    done
    
    export CONFIG_SOURCE
    export CONFIG_LOADED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    export PROJECT_NAME
    export PROJECT_STATE_DIR
    export PROJECT_URL
    
    _log_debug "Configuration exported successfully"
}

# Backup current configuration
_backup_current_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        _log_warning "No configuration file to backup"
        return 0
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$CONFIG_BACKUP_DIR/settings_${timestamp}.json"
    
    if cp "$CONFIG_FILE" "$backup_file"; then
        chmod 600 "$backup_file"
        _log_info "Configuration backed up to: $backup_file"
        
        find "$CONFIG_BACKUP_DIR" -name "settings_*.json" -type f | 
            sort -r | tail -n +11 | xargs -r rm -f
        
        return 0
    else
        _log_error "Failed to backup configuration"
        return 1
    fi
}

# Update systemd environment file with new OCID
_update_systemd_environment() {
    local new_ocid="$1"
    
    if [[ -z "$new_ocid" ]]; then
        _log_error "No OCID provided for systemd environment update"
        return 1
    fi
    
    _log_info "Updating systemd environment file..."
    
    cat > "$SYSTEMD_ENV_FILE" <<EOF
# ${PROJECT_NAME} - Environment Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source: Automated update via oci-setup.sh
OCI_SECRET_OCID=$new_ocid
EOF
    
    chmod 600 "$SYSTEMD_ENV_FILE"
    chown root:root "$SYSTEMD_ENV_FILE"
    
    if systemctl daemon-reload; then
        _log_success "Systemd environment updated successfully"
        return 0
    else
        _log_error "Failed to reload systemd daemon"
        return 1
    fi
}

# Get configuration value by key
_get_config_value() {
    local key="$1"
    
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        _log_error "Configuration not loaded"
        return 1
    fi
    
    if [[ -n "${CONFIG_VALUES[$key]:-}" ]]; then
        echo "${CONFIG_VALUES[$key]}"
        return 0
    else
        _log_error "Configuration key not found: $key"
        return 1
    fi
}

# Set configuration value (in memory only)
_set_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ -z "$key" ]] || [[ -z "$value" ]]; then
        _log_error "Both key and value must be provided"
        return 1
    fi
    
    CONFIG_VALUES["$key"]="$value"
    _log_debug "Configuration updated: $key"
}

# Display configuration summary (without sensitive values)
_display_config_summary() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        _log_error "Configuration not loaded"
        return 1
    fi
    
    _log_info "Configuration Summary:"
    _log_info "  Project: $PROJECT_NAME"
    _log_info "  Source: $CONFIG_SOURCE"
    _log_info "  Keys loaded: ${#CONFIG_VALUES[@]}"
    
    local safe_keys=("DOMAIN" "SMTP_HOST" "SMTP_FROM" "DATABASE_URL" "DOMAIN_NAME")
    for key in "${safe_keys[@]}"; do
        if [[ -n "${CONFIG_VALUES[$key]:-}" ]]; then
            _log_info "  $key: ${CONFIG_VALUES[$key]}"
        fi
    done
    
    local sensitive_keys=("ADMIN_TOKEN" "SMTP_PASSWORD" "BACKUP_PASSPHRASE")
    for key in "${sensitive_keys[@]}"; do
        if [[ -n "${CONFIG_VALUES[$key]:-}" ]]; then
            _log_info "  $key: [REDACTED]"
        fi
    done
}

# Get dynamic paths for use by other scripts
_get_project_paths() {
    echo "PROJECT_NAME=$PROJECT_NAME"
    echo "PROJECT_STATE_DIR=$PROJECT_STATE_DIR"
    echo "CONFIG_BACKUP_DIR=$CONFIG_BACKUP_DIR"
    echo "SYSTEMD_ENV_FILE=$SYSTEMD_ENV_FILE"
    echo "SERVICE_NAME=$SERVICE_NAME"
    echo "PROJECT_URL=$PROJECT_URL"
}

# Main configuration loading function
_load_configuration() {
    _log_debug "Initializing configuration system..."
    _init_config_system
    
    _load_systemd_environment
    
    if [[ -n "${OCI_SECRET_OCID:-}" ]]; then
        _log_debug "OCI_SECRET_OCID detected, using OCI Vault"
        if _load_from_oci_vault; then
            _export_configuration
            return 0
        else
            _log_warning "OCI Vault loading failed, falling back to local file"
            unset OCI_SECRET_OCID
        fi
    fi
    
    _log_debug "Using local configuration file"
    if _load_from_local_file; then
        _export_configuration
        return 0
    else
        _log_error "Failed to load configuration from any source"
        return 1
    fi
}

# Validate configuration completeness
_validate_configuration() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        _log_error "Configuration must be loaded before validation"
        return 1
    fi
    
    local errors=0
    
    if [[ -n "${CONFIG_VALUES[DOMAIN]:-}" ]]; then
        local domain="${CONFIG_VALUES[DOMAIN]}"
        if [[ ! "$domain" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && 
           [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            _log_error "Invalid domain format: $domain"
            ((errors++))
        fi
    fi
    
    if [[ -n "${CONFIG_VALUES[SMTP_HOST]:-}" ]] && [[ -n "${CONFIG_VALUES[SMTP_FROM]:-}" ]]; then
        if [[ ! "${CONFIG_VALUES[SMTP_FROM]}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            _log_error "Invalid SMTP_FROM email format: ${CONFIG_VALUES[SMTP_FROM]}"
            ((errors++))
        fi
    fi
    
    if [[ -n "${CONFIG_VALUES[DATABASE_URL]:-}" ]]; then
        if [[ ! "${CONFIG_VALUES[DATABASE_URL]}" =~ ^sqlite:// ]]; then
            _log_warning "Non-SQLite database detected: ${CONFIG_VALUES[DATABASE_URL]}"
        fi
    fi
    
    if [[ -n "${CONFIG_VALUES[ADMIN_EMAIL]:-}" ]]; then
        if [[ ! "${CONFIG_VALUES[ADMIN_EMAIL]}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            _log_error "Invalid ADMIN_EMAIL format: ${CONFIG_VALUES[ADMIN_EMAIL]}"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        _log_success "Configuration validation passed"
        return 0
    else
        _log_error "Configuration validation failed with $errors errors"
        return 1
    fi
}

load_config() {
    _load_configuration "$@"
}

get_config_value() {
    _get_config_value "$@"
}

set_config_value() {
    _set_config_value "$@"
}

display_config_summary() {
    _display_config_summary "$@"
}

validate_configuration() {
    _validate_configuration "$@"
}

backup_current_config() {
    _backup_current_config "$@"
}

get_project_paths() {
    _get_project_paths "$@"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _log_debug "lib/config.sh loaded successfully"
else
    _log_warning "lib/config.sh should be sourced, not executed directly"
    echo "Testing configuration loading..."
    _load_configuration
    _display_config_summary
fi