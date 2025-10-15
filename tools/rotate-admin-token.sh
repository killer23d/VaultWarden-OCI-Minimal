#!/usr/bin/env bash
# /tools/rotate-admin-token.sh - Rotates VaultWarden’s ADMIN_TOKEN and the Caddy Basic Auth password/hash used to protect /admin.
# Behavior:
#   - Generates a new 32-byte base64 ADMIN_TOKEN with openssl.
#   - Generates a new random Basic Auth password and hashes it with `caddy hash-password`.
#   - Updates settings.json with ADMIN_TOKEN and ADMIN_BASIC_AUTH_HASH atomically via jq.
#   - Enforces 600 perms on settings.json and restarts the stack to apply changes.
#   - Optional: If invoked with --upload-to-oci and OCI_SECRET_OCID is set, calls tools/update-secrets.sh to push the updated settings to OCI Vault.
# Requirements:
#   - jq, openssl, and caddy (for hash-password) available on the host.
#   - Project libraries (lib/config.sh, lib/logging.sh) for consistent logging and configuration.
# Usage:
#   ./tools/rotate-admin-token.sh [--upload-to-oci]

set -euo pipefail

# Auto-detect script location and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source required libraries
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"

_set_log_prefix "rotate-token"
_log_header "Admin Credential Rotation"

# Ensure the stack is running so we can use the Caddy container
if ! docker compose ps --services --filter "status=running" | grep -q "caddy"; then
    _log_error "The 'caddy' service is not running. Please start the stack first with ./startup.sh"
    exit 1
fi

# --- Step 1: Generate New Credentials ---
_log_info "Generating new admin token and basic auth password..."
NEW_ADMIN_TOKEN=$(openssl rand -base64 32)
NEW_BASIC_PASSWORD=$(openssl rand -base64 16)
_log_success "New credentials generated."

# --- Step 2: Hash the New Password Using the Caddy Container ---
_log_info "Hashing new basic auth password using the Caddy container..."
# The -T flag is important to disable pseudo-tty allocation for clean output
NEW_BASIC_HASH=$(docker compose exec -T caddy caddy hash-password --plaintext "$NEW_BASIC_PASSWORD" 2>/dev/null)
if [ -z "$NEW_BASIC_HASH" ]; then
    _log_error "Failed to hash password using the Caddy container."
    exit 1
fi
_log_success "Password hashed successfully."

# --- Step 3: Update the Configuration File ---
_log_info "Updating settings.json with new credentials..."
if ! jq \
   --arg token "$NEW_ADMIN_TOKEN" \
   --arg hash "$NEW_BASIC_HASH" \
   '.ADMIN_TOKEN = $token | .ADMIN_BASIC_AUTH_HASH = $hash' \
   "$ROOT_DIR/settings.json" > "$ROOT_DIR/settings.json.tmp"; then
   _log_error "Failed to update settings.json using jq."
   rm -f "$ROOT_DIR/settings.json.tmp"
   exit 1
fi
mv "$ROOT_DIR/settings.json.tmp" "$ROOT_DIR/settings.json"
chmod 600 "$ROOT_DIR/settings.json"
_log_success "settings.json updated."

# --- Step 4: Restart the Stack to Apply Changes ---
_log_info "Restarting the stack to apply new credentials..."
cd "$ROOT_DIR"
if ! ./startup.sh; then
    _log_error "Stack failed to restart. Please check the logs."
    exit 1
fi
_log_success "Stack restarted successfully."

# --- Step 5: Display New Credentials ---
echo
_log_header "New Admin Credentials (Save These Securely!)"
_log_info "These will only be displayed once."
echo
_print_key_value "New Basic Auth Username" "admin"
_print_key_value "New Basic Auth Password" "$NEW_BASIC_PASSWORD"
echo
_log_info "The new admin token is stored in settings.json and is required for the admin panel."
echo

