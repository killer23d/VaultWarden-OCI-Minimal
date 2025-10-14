#!/usr/bin/env bash
# startup.sh - Dynamic startup script for VaultWarden stack
#
# This script provides comprehensive startup management including:
# - Dynamic project detection and path configuration
# - Configuration loading from multiple sources (local/OCI Vault)
# - Runtime environment preparation and validation
# - Service orchestration with health checks
# - Integration with existing library ecosystem
#
# Dependencies: lib/logging.sh, lib/config.sh, lib/validation.sh, lib/system.sh
#

set -euo pipefail

# Auto-detect script location and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# Source existing libraries
source "$ROOT_DIR/lib/logging.sh"
# --- FIX: Source config lib to get centralized paths ---
source "$ROOT_DIR/lib/config.sh"
# --- END FIX ---
source "$ROOT_DIR/lib/validation.sh"
source "$ROOT_DIR/lib/system.sh"

# Set logging prefix for this script
_set_log_prefix "startup"

# Script constants
readonly COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

# Define required directories dynamically
# PROJECT_STATE_DIR is now sourced from lib/config.sh
REQUIRED_DIRS=(
    "$PROJECT_STATE_DIR"
    "$PROJECT_STATE_DIR/data"
    "$PROJECT_STATE_DIR/logs"
    "$PROJECT_STATE_DIR/logs/caddy"
    "$PROJECT_STATE_DIR/logs/vaultwarden"
    "$PROJECT_STATE_DIR/logs/fail2ban"
    "$PROJECT_STATE_DIR/logs/watchtower"
)

# Startup workflow
_startup_workflow() {
    _log_header "$PROJECT_NAME - Startup"

    # Step 1: System validation
    _validate_startup_prerequisites

    # Step 2: Configuration loading
    _log_info "Loading configuration..."
    if ! _load_configuration; then
        _log_error "Failed to load configuration"
        return 1
    fi

    # Step 3: Environment preparation
    _prepare_runtime_environment

    # Step 4: Pre-startup tasks
    _execute_pre_startup_tasks

    # Step 5: Start services
    _start_services

    # Step 6: Post-startup validation
    _validate_service_health

    _log_success "$PROJECT_NAME stack started successfully"
    _display_service_info
}

_validate_startup_prerequisites() {
    _log_info "Validating startup prerequisites..."

    # Use existing validation functions
    _validate_running_as_root
    _validate_docker_daemon
    _validate_compose_file "$COMPOSE_FILE"
    _validate_network_connectivity

    # Startup-specific validations
    if [[ ! -f "$ROOT_DIR/settings.json" ]] && [[ -z "${OCI_SECRET_OCID:-}" ]]; then
        _log_error "No configuration found."
        _log_info "This appears to be a fresh installation."
        _log_info "Please run: sudo ./tools/init-setup.sh"
        return 1
    fi
}

_prepare_runtime_environment() {
    _log_info "Preparing runtime environment..."

    # Create required directories using existing system functions
    for dir in "${REQUIRED_DIRS[@]}"; do
        _create_directory_secure "$dir" "755"
    done

    # --- FIX: Simplified placeholder creation ---
    # The Caddy container mounts ./caddy to /etc/caddy-extra, so we only need to manage the source file.
    local caddy_placeholder="$ROOT_DIR/caddy/cloudflare-ips.caddy"
    if [[ ! -f "$caddy_placeholder" ]]; then
        local parent_dir
        parent_dir="$(dirname "$caddy_placeholder")"
        [[ -d "$parent_dir" ]] || mkdir -p "$parent_dir"

        # Create a placeholder to prevent Caddy from failing on startup if the update script hasn't run yet.
        _create_file_secure "$caddy_placeholder" "644" "# Placeholder - will be populated by update scripts"
        _log_debug "Created Caddy placeholder: $caddy_placeholder"
    fi
    # --- END FIX ---

    # Create DDNS config directory and placeholder
    # NOTE: /etc/ddclient is a standard path for this service on Linux.
    local ddns_config_dir="/etc/ddclient"
    _create_directory_secure "$ddns_config_dir" "755"

    local ddns_config_file="$ddns_config_dir/ddclient.conf"
    if [[ ! -f "$ddns_config_file" ]]; then
        _create_file_secure "$ddns_config_file" "600" "# Placeholder - will be populated dynamically"
        _log_debug "Created DDNS config placeholder: $ddns_config_file"
    fi

    # Set proper permissions on sensitive files
    if [[ -f "$ROOT_DIR/settings.json" ]]; then
        chmod 600 "$ROOT_DIR/settings.json"
    fi

    # Export dynamic paths for docker-compose
    export PROJECT_STATE_DIR
    export PROJECT_NAME
}

_execute_pre_startup_tasks() {
    _log_info "Executing pre-startup tasks..."

    # Update Cloudflare IPs if script exists
    local cf_script="$ROOT_DIR/tools/update-cloudflare-ips.sh"
    if [[ -x "$cf_script" ]]; then
        _log_debug "Updating Cloudflare IP ranges..."
        if ! timeout 30 "$cf_script" --quiet 2>/dev/null; then
            _log_warning "Failed to update Cloudflare IPs, continuing with existing config"
        else
            _log_success "Cloudflare IPs updated successfully"
        fi
    fi

    # Render DDNS configuration if needed and script exists
    if [[ "${DDCLIENT_ENABLED:-false}" == "true" ]]; then
        local ddns_script="$ROOT_DIR/tools/render-ddclient-conf.sh"
        if [[ -x "$ddns_script" ]]; then
            _log_debug "Rendering DDNS configuration..."
            if ! timeout 15 "$ddns_script" 2>/dev/null; then
                _log_warning "Failed to render DDNS config, container will use environment variables"
            fi
        fi
    fi

    # Clean up any orphaned containers
    _cleanup_orphaned_containers
}

_start_services() {
    _log_info "Starting $PROJECT_NAME services..."

    # Change to root directory for compose
    cd "$ROOT_DIR"

    # Set compose project name dynamically
    export COMPOSE_PROJECT_NAME="$PROJECT_NAME"

    # Start services with dependency handling
    if docker compose -f "$COMPOSE_FILE" up -d --remove-orphans; then
        _log_success "Services started successfully"
    else
        _log_error "Failed to start services"
        _log_info "Check logs with: docker compose logs"
        return 1
    fi
}

_validate_service_health() {
    _log_info "Validating service health..."
    local max_retries=30
    local retry_delay=2
    local vaultwarden_container="${CONTAINER_NAME_VAULTWARDEN:-bw_vaultwarden}"

    _log_debug "Waiting for $vaultwarden_container to be healthy..."
    for ((i=1; i<=max_retries; i++)); do
        if docker compose ps --format json 2>/dev/null | jq -r ".[] | select(.Service==\"vaultwarden\") | .Health" 2>/dev/null | grep -q "healthy"; then
            _log_success "VaultWarden is healthy"
            break
        fi

        if [[ $i -eq $max_retries ]]; then
            _log_error "VaultWarden failed to become healthy"
            _show_troubleshooting_info
            return 1
        fi
        sleep $retry_delay
    done

    # Check other critical services
    local critical_services=("caddy" "fail2ban")
    for service in "${critical_services[@]}"; do
        if docker compose ps --format json 2>/dev/null | jq -r ".[] | select(.Service==\"$service\") | .State" 2>/dev/null | grep -q "running"; then
            _log_success "$service is running"
        else
            _log_warning "$service is not running properly"
        fi
    done
}


_show_troubleshooting_info() {
    _log_info "Troubleshooting Information:"
    _log_info "  View container status: docker compose ps"
    _log_info "  View all logs: docker compose logs"
    _log_info "  View VaultWarden logs: docker compose logs vaultwarden"
}

_display_service_info() {
    _log_header "Service Information"
    local domain
    domain=$(get_config_value "DOMAIN")

    _log_info "VaultWarden Web Interface:"
    _print_key_value "URL" "$domain"
    _print_key_value "Admin" "$domain/admin"
    echo
    _log_info "Service Management:"
    _print_key_value "Status" "docker compose ps"
    _print_key_value "Logs" "docker compose logs -f"
    _print_key_value "Stop" "docker compose down"
    echo
    _log_info "Project Paths:"
    _print_key_value "Data" "$PROJECT_STATE_DIR"
    _print_key_value "Config" "$ROOT_DIR/settings.json"
    _print_key_value "Logs" "$PROJECT_STATE_DIR/logs"
}

_cleanup_orphaned_containers() {
    _log_debug "Cleaning up orphaned containers..."
    docker container prune -f >/dev/null 2>&1 || true
    docker network prune -f >/dev/null 2>&1 || true
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        cat <<EOM
${BOLD}$PROJECT_NAME - Startup Script${NC}

${CYAN}USAGE:${NC}
  $0 [OPTIONS]

${CYAN}OPTIONS:${NC}
  --help, -h     Show this help message
  --validate     Validate configuration and prerequisites only

${CYAN}DYNAMIC CONFIGURATION:${NC}
  Project paths are automatically detected based on the repository name:
  • Project: $PROJECT_NAME
  • Data: $PROJECT_STATE_DIR

EOM
        exit 0
        ;;
    --validate)
        _log_header "$PROJECT_NAME Configuration Validation"
        _validate_startup_prerequisites
        _load_configuration
        _log_success "Validation completed successfully"
        exit 0
        ;;
    "")
        # No arguments, run normal startup
        _startup_workflow
        ;;
    *)
        _log_error "Unknown argument: $1"
        _log_info "Use --help for usage information"
        exit 1
        ;;
esac
