#!/usr/bin/env bash
# /tools/oci-setup.sh - Enhanced OCI Vault Setup with systemd Integration

set -euo pipefail

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/validation.sh"
source "$ROOT_DIR/lib/system.sh"

# NOTE: PROJECT_URL is now sourced dynamically from lib/config.sh

# Enhanced OCI setup with systemd integration
_setup_oci_vault() {
    local compartment_ocid vault_ocid key_ocid secret_name
    
    _log_info "Setting up OCI Vault integration..."
    
    if ! _validate_oci_cli; then
        _log_error "OCI CLI not configured properly"
        return 1
    fi
    
    # This function would contain the interactive prompts for OCI details
    # _prompt_oci_details
    
    # This function would handle the secret upload
    # new_secret_ocid=$(_upload_settings_to_vault "$compartment_ocid" "$vault_ocid" "$key_ocid" "$secret_name")
    
    if [[ -n "$new_secret_ocid" ]]; then
        _log_success "Secret uploaded successfully: $new_secret_ocid"
        _configure_systemd_persistence "$new_secret_ocid"
    else
        _log_error "Failed to upload secret to vault"
        return 1
    fi
}

_validate_oci_cli() {
    if ! _have_cmd oci >/dev/null 2>&1; then
        _log_error "OCI CLI not installed"
        return 1
    fi
    
    if ! oci iam user get --user-id "$(oci iam user list --query 'data[0].id' --raw-output 2>/dev/null)" >/dev/null 2>&1; then
        _log_error "OCI CLI not authenticated"
        return 1
    fi
    
    return 0
}

_configure_systemd_persistence() {
    local secret_ocid="$1"
    
    _log_info "Configuring systemd persistence for OCI secret..."
    
    printf "${CYAN}Would you like to configure systemd for automatic startup? [Y/n]: ${NC}"
    read -r response
    response=${response:-Y}
    
    case "$response" in
        [nN][oO]|[nN])
            _log_warning "Manual setup required:"
            _log_warning "  export OCI_SECRET_OCID=$secret_ocid"
            _log_warning "  Then run: ./startup.sh"
            return 0
            ;;
    esac
    
    local env_file="$SYSTEMD_ENV_FILE"
    _log_info "Creating systemd environment file: $env_file"
    
    cat > "$env_file" <<EOF
# ${PROJECT_NAME} - Environment Configuration
# Generated: $(date)
OCI_SECRET_OCID=$secret_ocid
EOF
    
    chmod 600 "$env_file"
    chown root:root "$env_file"
    
    local service_file="/etc/systemd/system/$SERVICE_NAME"
    _log_info "Creating systemd service: $service_file"
    
    cat > "$service_file" <<EOF
[Unit]
Description=${PROJECT_NAME} Stack
Documentation=${PROJECT_URL}
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=forking
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

# Environment
EnvironmentFile=-${env_file}
WorkingDirectory=${ROOT_DIR}
Environment=COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# Execution
ExecStartPre=/usr/bin/docker system prune -f --volumes
ExecStart=${ROOT_DIR}/startup.sh
ExecStop=${ROOT_DIR}/tools/stop-stack.sh
ExecReload=/bin/kill -HUP \$MAINPID

# Security
User=root
Group=root
PrivateDevices=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=${ROOT_DIR} /var/lib/docker /var/run/docker.sock

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    _log_success "Systemd service configured and enabled"
    
    printf "${CYAN}Would you like to start the service now? [Y/n]: ${NC}"
    read -r start_response
    start_response=${start_response:-Y}
    
    case "$start_response" in
        [yY][eE][sS]|[yY])
            _log_info "Starting ${PROJECT_NAME} service..."
            if systemctl start "$SERVICE_NAME"; then
                _log_success "Service started successfully"
                _log_info "Check status with: systemctl status ${SERVICE_NAME}"
                _log_info "View logs with: journalctl -fu ${SERVICE_NAME}"
            else
                _log_error "Failed to start service"
                return 1
            fi
            ;;
        *)
            _log_info "Start the service manually with:"
            _log_info "  systemctl start ${SERVICE_NAME}"
            ;;
    esac
}

# Main execution
main() {
    _log_header "${PROJECT_NAME} OCI Vault Setup"
    
    _validate_running_as_root
    _validate_docker_daemon
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        _log_warning "settings.json not found. Some operations may require it."
        _log_info "It is recommended to run ./tools/init-setup.sh first."
    fi
    
    case "${1:-}" in
        --update-ocid)
            if [[ -n "${2:-}" ]]; then
                _update_systemd_secret_ocid "$2" "$SYSTEMD_ENV_FILE"
                _restart_service_safely "$SERVICE_NAME"
            else
                _log_error "Usage: $0 --update-ocid <new-ocid>"
                exit 1
            fi
            ;;
        --systemd-only)
            if [[ -n "${2:-}" ]]; then
                _configure_systemd_persistence "$2"
            else
                _log_error "Usage: $0 --systemd-only <secret-ocid>"
                exit 1
            fi
            ;;
        *)
            _setup_oci_vault
            ;;
    esac
}

main "$@"