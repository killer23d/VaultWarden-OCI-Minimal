#!/usr/bin/env bash
# lib/config.sh - Configuration management with OCI Vault and systemd support

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_NAME="$(basename "$ROOT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
SERVICE_NAME="${PROJECT_NAME}.service"
PROJECT_STATE_DIR="/var/lib/${PROJECT_NAME}"
CONFIG_BACKUP_DIR="${PROJECT_STATE_DIR}/config-backups"
SYSTEMD_ENV_FILE="/etc/systemd/system/${PROJECT_NAME}.env"

_get_project_url() {
    if [[ -d "$ROOT_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
        local remote_url
        remote_url=$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            echo "${remote_url%.git}"
            return 0
        fi
    fi
    echo "https://github.com/your-username/your-forked-repo"
}
PROJECT_URL="$(_get_project_url)"

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
        # Use the configured timeout from settings.json, defaulting to 15s
        local oci_timeout="${OCI_VAULT_TIMEOUT:-15}"
        _log_debug "Attempting to fetch secret (attempt $i/$max_retries, timeout: ${oci_timeout}s)"

        # Wrap the OCI CLI call with the timeout command
        if secret_content=$(timeout "${oci_timeout}" oci vault secret get-secret-bundle \
            --secret-id "$OCI_SECRET_OCID" \
            --query 'data."secret-bundle-content".content' \
            --raw-output 2>/dev/null); then
            
            break # Success, exit the loop
        else
            local exit_code=$?
            # Exit code 124 specifically means the timeout was exceeded
            if [[ $exit_code -eq 124 ]]; then
                _log_warning "OCI Vault request timed out after ${oci_timeout}s."
            else
                _log_warning "Failed to fetch secret from OCI Vault (exit code: $exit_code)."
            fi

            if [[ $i -eq $max_retries ]]; then
                _log_error "Failed to fetch secret after $max_retries attempts. Will now attempt fallback."
                return 1
            fi
            
            _log_info "Retrying in ${retry_delay}s..."
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

    _log_debug "Parsed ${#CONFIG_VALUES[@]} configuration keys"
    return 0
}

# Export configuration as environment variables for docker-compose
_export_configuration() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        _log_error "Configuration not loaded. Call load_config first."
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
        
        find "$CONFIG_BACKUP_DIR" -name "settings_*.json" -type f | \
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
get_config_value() {
    local key="$1"
    
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        return 1
    fi
    
    if [[ -n "${CONFIG_VALUES[$key]:-}" ]]; then
        echo "${CONFIG_VALUES[$key]}"
        return 0
    else
        return 1
    fi
}

# Main configuration loading function
load_config() {
    _log_debug "Initializing configuration system..."
    _init_config_system
    
    _load_systemd_environment
    
    local oci_expected=false
    if [[ -n "${OCI_SECRET_OCID:-}" ]]; then
        oci_expected=true
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
        # Validate that local config is not stale if OCI was expected
        if [[ "$oci_expected" == "true" ]]; then
            _log_warning "Using potentially stale local configuration due to OCI Vault unavailability"
            _log_info "Consider running ./tools/oci-setup.sh to verify cloud configuration"
        fi
        _export_configuration
        return 0
    else
        _log_error "Failed to load configuration from any source"
        return 1
    fi
}

# Validate configuration completeness
validate_configuration() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        _log_error "Configuration must be loaded before validation"
        return 1
    fi
    
    local errors=0
    
    if [[ -z "${CONFIG_VALUES[DOMAIN]:-}" ]]; then
        _log_error "Required configuration key missing: DOMAIN"
        ((errors++))
    elif [[ ! "${CONFIG_VALUES[DOMAIN]}" =~ ^https?://[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$ ]]; then
        _log_error "Invalid DOMAIN format: ${CONFIG_VALUES[DOMAIN]}"
        ((errors++))
    fi

    if [[ -z "${CONFIG_VALUES[ADMIN_TOKEN]:-}" ]]; then
        _log_error "Required configuration key missing: ADMIN_TOKEN"
        ((errors++))
    fi
    
    if [[ -n "${CONFIG_VALUES[ADMIN_EMAIL]:-}" ]]; then
        if [[ ! "${CONFIG_VALUES[ADMIN_EMAIL]}" =~ ^[^@]+@[^@]+\\.[^@]+$ ]]; then
            _log_error "Invalid ADMIN_EMAIL format: ${CONFIG_VALUES[ADMIN_EMAIL]}"
            ((errors++))
        fi
    fi

    # Validate memory limit formats
    local mem_vars=("VAULTWARDEN_MEMORY_LIMIT" "VAULTWARDEN_MEMORY_RESERVATION" "CADDY_MEMORY_LIMIT" "FAIL2BAN_MEMORY_LIMIT")
    for mem_var in "${mem_vars[@]}"; do
        if [[ -n "${CONFIG_VALUES[$mem_var]:-}" ]]; then
            local mem_limit="${CONFIG_VALUES[$mem_var]}"
            if [[ ! "$mem_limit" =~ ^[0-9]+[gGmMkK]?$ ]]; then
                _log_error "Invalid memory format for $mem_var: $mem_limit (e.g., 512M, 1G)"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        _log_success "Configuration validation passed"
        return 0
    else
        _log_error "Configuration validation failed with $errors errors"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _log_debug "lib/config.sh loaded successfully"
else
    _log_warning "lib/config.sh should be sourced, not executed directly"
    echo "Testing configuration loading..."
    load_config
    validate_configuration
fi
