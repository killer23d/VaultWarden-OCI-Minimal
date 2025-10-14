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
    local compartment_ocid vault_ocid key_ocid secret_name new_secret_ocid
    
    _log_info "Setting up OCI Vault integration..."
    
    if ! _validate_oci_cli; then
        _log_error "OCI CLI not configured properly"
        return 1
    fi
    
    # This function would contain the interactive prompts for OCI details
    # For this script, we'll assume the user provides the secret OCID
    _log_prompt "Enter the OCID of the OCI Vault Secret"
    read -r new_secret_ocid

    if [[ -n "$new_secret_ocid" ]]; then
        _log_success "Secret OCID provided: ${new_secret_ocid:0:25}..."
        _configure_systemd_persistence "$new_secret_ocid"
    else
        _log_error "No Secret OCID provided. Aborting."
        return 1
    fi
}

_validate_oci_cli() {
    if ! _have_cmd oci >/dev/null 2>&1; then
        _log_error "OCI CLI not installed"
        _log_info "Please install and configure it first. See OCI documentation."
        return 1
    fi
    
    if ! oci iam region list >/dev/null 2>&1; then
        _log_error "OCI CLI not authenticated. Please run 'oci setup config'."
        return 1
    fi
    
    _log_success "OCI CLI is configured and authenticated."
    return 0
}

_configure_systemd_persistence() {
    local secret_ocid="$1"
    
    _log_info "Configuring systemd persistence for OCI secret..."
    
    printf "${CYAN}Would you like to create/update the systemd service for automatic startup? [Y/n]: ${NC}"
    read -r response
    response=${response:-Y}
    
    case "$response" in
        [nN][oO]|[nN])
            _log_warning "Systemd service not configured. Manual setup required:"
            _log_warning "  1. Create ${SYSTEMD_ENV_FILE} with OCI_SECRET_OCID=${secret_ocid}"
            _log_warning "  2. Run: ./startup.sh"
            return 0
            ;;
    esac
    
    _log_info "Creating systemd environment file: $SYSTEMD_ENV_FILE"
    
    cat > "$SYSTEMD_ENV_FILE" <<EOF
# ${PROJECT_NAME} - Environment Configuration
# Generated: $(date)
OCI_SECRET_OCID=$secret_ocid
EOF
    
    chmod 600 "$SYSTEMD_ENV_FILE"
    chown root:root "$SYSTEMD_ENV_FILE"
    
    local service_file="/etc/systemd/system/$SERVICE_NAME"
    _log_info "Creating systemd service file: $service_file"
    
    cat > "$service_file" <<EOF
[Unit]
Description=${PROJECT_NAME} Stack
Documentation=${PROJECT_URL}
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

# Environment
EnvironmentFile=-${SYSTEMD_ENV_FILE}
WorkingDirectory=${ROOT_DIR}
Environment=COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# Execution
ExecStart=${ROOT_DIR}/startup.sh
ExecStop=/usr/bin/docker compose -f ${ROOT_DIR}/docker-compose.yml down
ExecReload=/bin/kill -HUP \$MAINPID

# Security
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    _enable_service "$SERVICE_NAME"
    
    _log_success "Systemd service configured and enabled"
    
    printf "${CYAN}Would you like to start the service now? [Y/n]: ${NC}"
    read -r start_response
    start_response=${start_response:-Y}
    
    case "$start_response" in
        [yY][eE][sS]|[yY])
            _log_info "Starting ${PROJECT_NAME} service..."
            if _start_service "$SERVICE_NAME"; then
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