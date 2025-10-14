#!/usr/bin/env bash
# tools/init-setup.sh - Dynamic initial system setup
#
# This script provides comprehensive system initialization leveraging
# the existing library ecosystem for consistent operations and logging.
#
# Dependencies: lib/logging.sh, lib/validation.sh, lib/system.sh
#

set -euo pipefail

# Auto-detect script location and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source existing libraries
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/validation.sh"
source "$ROOT_DIR/lib/system.sh"

# Set logging prefix for this script
_set_log_prefix "init"

# Setup constants
readonly REQUIRED_PACKAGES=("docker.io" "docker-compose-plugin" "jq" "curl" "openssl")
readonly OPTIONAL_PACKAGES=("fail2ban" "ufw" "gettext")

# --- FIX: New function to validate script permissions ---
_validate_script_permissions() {
    _log_section "Validating Script Permissions"
    local errors=0
    local scripts_to_check=(
        "$ROOT_DIR/startup.sh"
        "$ROOT_DIR/tools/monitor.sh"
        "$ROOT_DIR/tools/db-backup.sh"
        "$ROOT_DIR/tools/create-full-backup.sh"
        "$ROOT_DIR/tools/restore.sh"
        "$ROOT_DIR/tools/sqlite-maintenance.sh"
        "$ROOT_DIR/tools/update-cloudflare-ips.sh"
    )

    for script in "${scripts_to_check[@]}"; do
        if [[ ! -x "$script" ]]; then
            _log_error "Script not executable: $script"
            _log_info "Run 'chmod +x $script' to fix."
            ((errors++))
        else
            _log_debug "Script is executable: $script"
        fi
    done

    if [[ $errors -gt 0 ]]; then
        _log_error "Please fix the script permissions and run again."
        exit 1
    fi
    _log_success "All scripts are executable."
}
# --- END FIX ---

# Parse command line arguments first
AUTO_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --help|-h)
            cat <<EOF
${BOLD}$PROJECT_NAME - Initial Setup${NC}

${CYAN}USAGE:${NC}
  $0 [OPTIONS]

${CYAN}OPTIONS:${NC}
  --auto         Run in automated mode with minimal prompts
  --help, -h     Show this help message

${CYAN}DYNAMIC CONFIGURATION:${NC}
  All paths are automatically detected based on repository location:
  • Project: $PROJECT_NAME
  • Data: $PROJECT_STATE_DIR
  • Service: ${PROJECT_NAME}.service

EOF
            exit 0
            ;;
        *)
            _log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Main initialization workflow
_init_setup_workflow() {
    _log_header "$PROJECT_NAME - Initial Setup"

    # Display project information
    _log_info "Project Details:"
    _print_key_value "Name" "$PROJECT_NAME"
    _print_key_value "Root" "$ROOT_DIR"
    _print_key_value "Data" "$PROJECT_STATE_DIR"
    _print_key_value "Mode" "$([ "$AUTO_MODE" == "true" ] && echo "Automated" || echo "Interactive")"
    echo

    # Step 1: System validation and preparation
    _validate_script_permissions
    _validate_system_requirements

    # Step 2: Package installation
    _install_required_packages

    # Step 3: Docker setup and validation
    _setup_docker_environment

    # Step 4: System security configuration
    _configure_system_security

    # Step 5: Generate initial configuration
    _generate_initial_configuration

    # Step 6: Create system directories and files
    _create_system_structure

    # Step 6a: Configure fail2ban Cloudflare integration
    _configure_cloudflare_fail2ban

    # Step 6b: Setup automated maintenance via cron
    _setup_cron_jobs

    # Step 7: Final validation
    _validate_setup_completion

    _log_success "Initial setup completed successfully!"
    _display_next_steps
}

_validate_system_requirements() {
    _log_section "System Requirements Validation"

    # Use existing validation functions
    _validate_running_as_root
    _validate_os_compatibility
    _validate_system_resources
    _validate_network_connectivity

    # Setup-specific validations
    if [[ -f "$CONFIG_FILE" ]]; then
        _log_warning "Configuration file already exists: $CONFIG_FILE"
        if [[ "$AUTO_MODE" != "true" ]]; then
            _log_confirm "Overwrite existing configuration?"
            read -r response
            if [[ ! "$response" =~ ^[yY][eE][sS]?$ ]]; then
                _log_info "Setup cancelled by user"
                exit 0
            fi
        fi
    fi
}

_install_required_packages() {
    _log_section "Package Installation"

    # Update package index using existing system functions
    _update_package_index

    # Install required packages
    for package in "${REQUIRED_PACKAGES[@]}"; do
        _install_package "$package"
    done

    # Install optional packages with user consent
    if [[ "$AUTO_MODE" != "true" ]]; then
        _log_confirm "Install optional security packages (fail2ban, ufw)?" "Y"
        read -r response
        response=${response:-Y}

        if [[ "$response" =~ ^[yY][eE][sS]?$ ]]; then
            for package in "${OPTIONAL_PACKAGES[@]}"; do
                _install_package "$package"
            done
        fi
    else
        # Auto mode installs optional packages
        for package in "${OPTIONAL_PACKAGES[@]}"; do
            _install_package "$package"
        done
    fi
}

_setup_docker_environment() {
    _log_section "Docker Environment Setup"

    # Enable and start Docker using existing functions
    _enable_service "docker"
    _start_service "docker"

    # Validate Docker daemon
    _validate_docker_daemon
    _validate_docker_compose

    # Add current user to docker group if not root-only
    local current_sudo_user="${SUDO_USER:-}"
    if [[ -n "$current_sudo_user" ]] && [[ "$current_sudo_user" != "root" ]]; then
        _log_info "Adding user $current_sudo_user to docker group..."
        usermod -aG docker "$current_sudo_user"
        _log_info "User will need to log out and back in for group changes to take effect"
    fi
}

_configure_system_security() {
    _log_section "System Security Configuration"

    # Configure UFW firewall if installed
    if command -v ufw >/dev/null 2>&1; then
        _log_info "Configuring UFW firewall..."

        # Basic UFW configuration
        ufw --force enable >/dev/null 2>&1
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1

        # Allow SSH (current session)
        ufw allow ssh >/dev/null 2>&1

        # Allow HTTP/HTTPS
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1

        _log_success "UFW firewall configured"

        if [[ "$AUTO_MODE" != "true" ]]; then
            _log_info "Current UFW rules:"
            ufw status numbered
        fi
    fi

    # Enable fail2ban service if installed (configuration is already in ./fail2ban/)
    if command -v fail2ban-client >/dev/null 2>&1; then
        _log_info "Enabling fail2ban service..."
        _enable_service "fail2ban"
        _start_service "fail2ban"
        _log_success "fail2ban service enabled (configuration will be loaded from Docker mount)"
    fi
}

_setup_cron_jobs() {
    _log_section "Cron Job Configuration"

    local project_root="$ROOT_DIR"
    local cron_file="/tmp/vaultwarden-cron"

    # Create cron job entries
    cat > "$cron_file" <<EOF
# ${PROJECT_NAME} - Automated Maintenance Schedule
# Generated by init-setup.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Database maintenance
0 2 * * 1 root cd $project_root && ./tools/sqlite-maintenance.sh -t full 2>&1 | logger -t sqlite-maintenance
0 6 * * * root cd $project_root && ./tools/sqlite-maintenance.sh -t quick 2>&1 | logger -t sqlite-maintenance

# System monitoring (every 5 minutes)
*/5 * * * * root cd $project_root && ./tools/monitor.sh 2>&1 | logger -t monitor

# Backup jobs (daily at 1 AM, weekly full backup on Sunday)
0 1 * * * root cd $project_root && ./tools/db-backup.sh 2>&1 | logger -t backup
0 0 * * 0 root cd $project_root && ./tools/create-full-backup.sh 2>&1 | logger -t full-backup

# Cloudflare IP updates (daily at 3 AM)
0 3 * * * root cd $project_root && ./tools/update-cloudflare-ips.sh --quiet 2>&1 | logger -t cloudflare-ips

# Log rotation and cleanup (daily at 4 AM)
0 4 * * * root find $project_root/logs -name "*.log" -size +50M -exec truncate -s 10M {} \; 2>&1 | logger -t log-cleanup
0 4 * * * root find /var/lib/${PROJECT_NAME}/backups -name "*.backup*" -mtime +30 -delete 2>&1 | logger -t backup-cleanup

EOF

    # Install cron jobs
    if [[ "$AUTO_MODE" != "true" ]]; then
        _log_confirm "Install automated maintenance cron jobs?" "Y"
        read -r response
        response=${response:-Y}

        if [[ ! "$response" =~ ^[yY][eE][sS]?$ ]]; then
            _log_info "Cron job installation skipped"
            rm -f "$cron_file"
            return 0
        fi
    fi

    # Install the cron jobs
    if crontab -l > /dev/null 2>&1; then
        # Backup existing crontab
        local backup_cron="/tmp/crontab-backup-$(date +%Y%m%d_%H%M%S)"
        crontab -l > "$backup_cron"
        _log_info "Existing crontab backed up to: $backup_cron"

        # Merge with existing crontab
        (crontab -l; echo; cat "$cron_file") | crontab -
    else
        # No existing crontab, install fresh
        crontab "$cron_file"
    fi

    # Cleanup temporary file
    rm -f "$cron_file"

    _log_success "Cron jobs installed successfully"

    # Display installed jobs
    if [[ "$AUTO_MODE" != "true" ]]; then
        _log_info "Installed cron schedule:"
        echo "  Database maintenance: Weekly full (Mon 2AM), Daily quick (6AM)"
        echo "  System monitoring: Every 5 minutes"
        echo "  Backups: Daily database (1AM), Weekly full (Sun 12AM)"
        echo "  Cloudflare IPs: Daily update (3AM)"
        echo "  Cleanup: Daily log rotation and old backup removal (4AM)"
    fi

    # Enable cron service
    _enable_service "cron" || _enable_service "crond" || {
        _log_warning "Could not enable cron service automatically"
        _log_info "Ensure cron service is running: systemctl enable --now cron"
    }

    return 0
}

_configure_cloudflare_fail2ban() {
    _log_section "Cloudflare Fail2Ban Integration"

    local cloudflare_conf="$ROOT_DIR/fail2ban/action.d/cloudflare.conf"
    local cloudflare_email="${CLOUDFLARE_EMAIL:-}"
    local cloudflare_api_key="${CLOUDFLARE_API_KEY:-}"

    # Check if template file exists
    if [[ ! -f "$cloudflare_conf" ]]; then
        _log_warning "Cloudflare fail2ban template not found: $cloudflare_conf"
        return 0
    fi

    # Load configuration if not already loaded
    if [[ -z "$cloudflare_email" ]] && [[ -f "$CONFIG_FILE" ]]; then
        cloudflare_email=$(jq -r '.CLOUDFLARE_EMAIL // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        cloudflare_api_key=$(jq -r '.CLOUDFLARE_API_KEY // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi

    # Prompt for Cloudflare credentials if not provided
    if [[ -z "$cloudflare_email" ]] && [[ "$AUTO_MODE" != "true" ]]; then
        _log_info "Configuring Cloudflare integration for fail2ban"
        _log_prompt "Enter Cloudflare email (leave blank to skip)"
        read -r cloudflare_email

        if [[ -n "$cloudflare_email" ]]; then
            _log_prompt "Enter Cloudflare Global API Key"
            read -r -s cloudflare_api_key
            echo
        fi
    fi

    # Apply configuration if credentials are available
    if [[ -n "$cloudflare_email" ]] && [[ -n "$cloudflare_api_key" ]]; then
        _log_info "Configuring Cloudflare fail2ban integration..."

        # Replace template variables
        sed -i.bak \
            -e "s/{{CLOUDFLARE_EMAIL}}/$cloudflare_email/g" \
            -e "s/{{CLOUDFLARE_API_KEY}}/$cloudflare_api_key/g" \
            "$cloudflare_conf"

        # Secure the configuration file
        chmod 600 "$cloudflare_conf"

        _log_success "Cloudflare fail2ban integration configured"

        # Update settings.json with Cloudflare credentials if not already present
        if [[ -f "$CONFIG_FILE" ]]; then
            local temp_config
            temp_config=$(mktemp)

            jq --arg email "$cloudflare_email" --arg key "$cloudflare_api_key" \
               '.CLOUDFLARE_EMAIL = $email | .CLOUDFLARE_API_KEY = $key' \
               "$CONFIG_FILE" > "$temp_config" && mv "$temp_config" "$CONFIG_FILE"

            chmod 600 "$CONFIG_FILE"
        fi

    else
        _log_info "Cloudflare integration skipped (no credentials provided)"
        _log_info "You can configure this later by editing $cloudflare_conf"
    fi
}

_generate_initial_configuration() {
    _log_section "Configuration Generation"

    local domain smtp_host smtp_from smtp_username smtp_password admin_email

    if [[ "$AUTO_MODE" == "true" ]]; then
        # Auto mode uses placeholder values
        domain="https://localhost"
        admin_email="admin@localhost"
        smtp_host="smtp.gmail.com"
        smtp_from="noreply@localhost"
        smtp_username=""
        smtp_password=""
    else
        # Interactive mode prompts for values
        _log_prompt "Enter your domain name (e.g., https://vault.example.com)"
        read -r domain

        _log_prompt "Enter admin email address"
        read -r admin_email

        _log_prompt "Enter SMTP host" "smtp.gmail.com"
        read -r smtp_host
        smtp_host=${smtp_host:-smtp.gmail.com}

        _log_prompt "Enter SMTP from address"
        read -r smtp_from

        _log_prompt "Enter SMTP username (optional)"
        read -r smtp_username

        _log_prompt "Enter SMTP password (optional)"
        read -r -s smtp_password
        echo
    fi

    # Generate secure random tokens using OpenSSL
    local admin_token backup_passphrase
    admin_token=$(openssl rand -base64 32)
    backup_passphrase=$(openssl rand -base64 32)

    # Create configuration JSON with dynamic paths
    _create_configuration_file "$domain" "$admin_email" "$smtp_host" "$smtp_from" "$smtp_username" "$smtp_password" "$admin_token" "$backup_passphrase"

    _log_success "Initial configuration generated"

    if [[ "$AUTO_MODE" != "true" ]]; then
        _log_info "Admin token: ${admin_token:0:8}... (truncated for security)"
        _log_warning "Save the admin token securely - needed for web admin access"
    fi
}

_create_configuration_file() {
    local domain="$1" admin_email="$2" smtp_host="$3" smtp_from="$4" smtp_username="$5" smtp_password="$6" admin_token="$7" backup_passphrase="$8"

    # Extract app domain from full domain URL
    local app_domain="${domain#https://}"
    local domain_name
    domain_name=$(echo "$app_domain" | sed 's/^[^.]*\.//')

    # Build configuration JSON
    cat > "$CONFIG_FILE" <<EOF
{
  "DOMAIN_NAME": "${domain_name}",
  "APP_DOMAIN": "${app_domain}",
  "DOMAIN": "${domain}",
  "ADMIN_EMAIL": "${admin_email}",
  "ADMIN_TOKEN": "${admin_token}",
  "BACKUP_PASSPHRASE": "${backup_passphrase}",
  "DATABASE_URL": "sqlite:///data/db.sqlite3",
  "ROCKET_WORKERS": 1,
  "WEBSOCKET_ENABLED": false,
  "SIGNUPS_ALLOWED": false,
  "SMTP_HOST": "${smtp_host}",
  "SMTP_PORT": 587,
  "SMTP_SECURITY": "starttls",
  "SMTP_USERNAME": "${smtp_username}",
  "SMTP_PASSWORD": "${smtp_password}",
  "SMTP_FROM": "${smtp_from}",
  "PUSH_ENABLED": false,
  "PUSH_INSTALLATION_ID": "",
  "PUSH_INSTALLATION_KEY": "",
  "PUSH_RELAY_URI": "https://api.bitwarden.com",
  "DDCLIENT_ENABLED": false,
  "DDCLIENT_PROTOCOL": "cloudflare",
  "DDCLIENT_LOGIN": "",
  "DDCLIENT_PASSWORD": "",
  "DDCLIENT_ZONE": "${domain_name}",
  "DDCLIENT_HOST": "${app_domain}",
  "CLOUDFLARE_EMAIL": "",
  "CLOUDFLARE_API_KEY": "",
  "BACKUP_KEEP_DB": 30,
  "BACKUP_KEEP_FULL": 8
}
EOF

    # Secure the configuration file
    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"

    # Validate the generated JSON
    if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        _log_error "Generated configuration file contains invalid JSON"
        return 1
    fi

    _log_success "Configuration file created: $CONFIG_FILE"
}

_create_system_structure() {
    _log_section "System Structure Creation"

    # Create required directories using existing system functions
    local directories=(
        "$PROJECT_STATE_DIR"
        "$PROJECT_STATE_DIR/data/bwdata"
        "$PROJECT_STATE_DIR/logs/caddy"
        "$PROJECT_STATE_DIR/logs/vaultwarden"
        "$PROJECT_STATE_DIR/logs/fail2ban"
        "$PROJECT_STATE_DIR/logs/watchtower"
        "$PROJECT_STATE_DIR/backups"
        "$PROJECT_STATE_DIR/state"
        "$PROJECT_STATE_DIR/caddy_data"
        "$PROJECT_STATE_DIR/caddy_config"
        "/etc/caddy-extra"
        "$ROOT_DIR/data"
        "$ROOT_DIR/logs"
        "$ROOT_DIR/caddy"
        "$ROOT_DIR/ddclient"
    )

    for dir in "${directories[@]}"; do
        _create_directory_secure "$dir" "755"
    done

    # Create symlinks for backward compatibility with docker-compose paths
    local symlinks=(
        "$ROOT_DIR/data/bwdata:$PROJECT_STATE_DIR/data/bwdata"
        "$ROOT_DIR/logs/caddy:$PROJECT_STATE_DIR/logs/caddy"
        "$ROOT_DIR/logs/vaultwarden:$PROJECT_STATE_DIR/logs/vaultwarden"
        "$ROOT_DIR/logs/fail2ban:$PROJECT_STATE_DIR/logs/fail2ban"
        "$ROOT_DIR/logs/watchtower:$PROJECT_STATE_DIR/logs/watchtower"
    )

    for symlink in "${symlinks[@]}"; do
        local link_src="${symlink%:*}"
        local link_dst="${symlink#*:}"

        if [[ ! -e "$link_src" ]]; then
            ln -s "$link_dst" "$link_src" 2>/dev/null || true
            _log_debug "Created symlink: $link_src -> $link_dst"
        fi
    done

    # Create placeholder files
    local placeholders=(
        "/etc/caddy-extra/cloudflare-ips.caddy"
        "$ROOT_DIR/caddy/cloudflare-ips.caddy"
        "$ROOT_DIR/ddclient/ddclient.conf"
    )

    for placeholder in "${placeholders[@]}"; do
        if [[ "$placeholder" == *"ddclient.conf" ]]; then
            _create_file_secure "$placeholder" "600" "# DDNS Configuration - Placeholder\n# This file will be updated by tools/render-ddclient-conf.sh\nprotocol=cloudflare\nuse=web\nssl=yes"
        else
            _create_file_secure "$placeholder" "644" "# Placeholder - will be populated by update scripts"
        fi
    done

    # Create state tracking file
    cat > "$PROJECT_STATE_DIR/state/project-info" <<EOF
PROJECT_NAME=$PROJECT_NAME
PROJECT_STATE_DIR=$PROJECT_STATE_DIR
INITIALIZED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ROOT_DIR=$ROOT_DIR
SCRIPT_VERSION=1.0.0
EOF

    chmod 600 "$PROJECT_STATE_DIR/state/project-info"

    _log_success "System structure created successfully"
}

_validate_setup_completion() {
    _log_section "Setup Validation"

    # Validate configuration file
    if [[ ! -f "$CONFIG_FILE" ]] || ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        _log_error "Configuration file validation failed"
        return 1
    fi

    # Validate Docker using existing functions
    _validate_docker_daemon
    _validate_docker_compose

    # Validate required directories
    local critical_dirs=("$PROJECT_STATE_DIR" "/etc/caddy-extra" "$ROOT_DIR/data" "$ROOT_DIR/logs" "$ROOT_DIR/ddclient")
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            _log_error "Required directory not created: $dir"
            return 1
        fi
    done

    _log_success "Setup validation completed successfully"
}

_display_next_steps() {
    echo
    _log_header "Setup Complete - Next Steps"

    _log_numbered_item 1 "Review and customize configuration:"
    _log_info "   nano $CONFIG_FILE"
    echo

    _log_numbered_item 2 "Start $PROJECT_NAME:"
    _log_info "   ./startup.sh"
    echo

    _log_numbered_item 3 "Optional - Configure OCI Vault integration:"
    _log_info "   ./tools/oci-setup.sh"
    echo

    _log_numbered_item 4 "Access $PROJECT_NAME:"
    local domain
    domain=$(jq -r '.DOMAIN // "your-domain"' "$CONFIG_FILE" 2>/dev/null)
    _log_info "   Web: $domain"
    _log_info "   Admin: $domain/admin"
    echo

    _log_info "Project Information:"
    _print_key_value "Name" "$PROJECT_NAME"
    _print_key_value "Data Directory" "$PROJECT_STATE_DIR" 
    _print_key_value "Service Name" "${PROJECT_NAME}.service"
}

# Execute main workflow
_init_setup_workflow
