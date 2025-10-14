#!/usr/bin/env bash
# tools/update-secrets.sh - Secure secret rotation and OCI Vault management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load libraries
for lib in logging system config validation; do
  lib_file="$ROOT_DIR/lib/${lib}.sh"
  if [[ -f "$lib_file" ]]; then
    # shellcheck source=/dev/null
    source "$lib_file"
  else
    echo "ERROR: Required library not found: $lib_file" >&2
    exit 1
  fi
done

_set_log_prefix "update-secrets"

ACTION="${ACTION:-rotate-local}"
SETTINGS_FILE="${SETTINGS_FILE:-$ROOT_DIR/settings.json}"
DRY_RUN="${DRY_RUN:-false}"
CREATE_BACKUP="${CREATE_BACKUP:-true}"

_display_usage() {
  cat <<USAGE
Usage: $(basename "$0") [action]
Actions:
  rotate-local     Rotate local secrets in settings.json
  create-oci       Create a new OCI Vault secret from settings.json
  update-oci       Update an existing OCI Vault secret
  sync-from-oci    Sync settings.json from an OCI Vault secret
  generate-tokens  Generate tokens and print to stdout
Environment:
  SETTINGS_FILE, DRY_RUN, CREATE_BACKUP, OCI_SECRET_OCID
USAGE
}

_generate_admin_token() { openssl rand -hex 32; }
_generate_backup_passphrase() { openssl rand -base64 48 | tr -d '\n'; }
_generate_smtp_password() { openssl rand -base64 32 | tr -d '\n'; }

_rotate_local_secrets() {
  local settings_file="$1"
  _log_header "Rotating Local Secrets"

  [[ -f "$settings_file" ]] || { _log_error "Settings file not found: $settings_file"; return 1; }
  _have_cmd jq || { _log_error "jq is required"; return 1; }

  if [[ "$CREATE_BACKUP" == "true" ]]; then
    _backup_file "$settings_file" || _log_warning "Failed to create backup"
  fi

  local new_admin_token new_backup_passphrase new_smtp_password
  new_admin_token="$(_generate_admin_token)"
  new_backup_passphrase="$(_generate_backup_passphrase)"
  new_smtp_password="$(_generate_smtp_password)"

  if [[ "$DRY_RUN" == "true" ]]; then
    _log_info "[DRY RUN] Would update tokens in $settings_file"
    _log_info " ADMIN_TOKEN: ${new_admin_token:0:8}...***"
    _log_info " BACKUP_PASSPHRASE: ${new_backup_passphrase:0:8}...***"
    _log_info " SMTP_PASSWORD: ${new_smtp_password:0:8}...***"
    return 0
  fi

  local tmp; tmp="$(mktemp)"
  if jq \
    --arg admin "$new_admin_token" \
    --arg pass "$new_backup_passphrase" \
    --arg smtp "$new_smtp_password" \
    '
    .ADMIN_TOKEN = $admin |
    .BACKUP_PASSPHRASE = $pass |
    .SMTP_PASSWORD = $smtp
    ' "$settings_file" > "$tmp"; then
    mv "$tmp" "$settings_file"
    chmod 600 "$settings_file"
    _log_success "Local secrets rotated successfully"
    _log_info "New ADMIN_TOKEN: ${new_admin_token:0:8}...*** ($(echo -n "$new_admin_token" | wc -c) characters)"
    _log_info "New BACKUP_PASSPHRASE: ${new_backup_passphrase:0:8}...*** ($(echo -n "$new_backup_passphrase" | wc -c) characters)"
    _log_warning "IMPORTANT: Restart VaultWarden service to apply new secrets"
    _log_info " docker compose restart vaultwarden"
    return 0
  else
    rm -f "$tmp"
    _log_error "Failed to update settings file"
    return 1
  fi
}

_create_oci_secret() {
    _log_header "Creating OCI Vault Secret"
    _log_error "The 'create-oci' action is not fully implemented for safety."
    _log_info "Creating secrets requires Compartment, Vault, and Key OCIDs, which are best handled manually."
    _log_info "Please follow these steps to create the secret using the OCI CLI:"
    echo
    _log_numbered_item 1 "Encode your settings.json file:"
    _log_info "   cat $SETTINGS_FILE | base64 -w 0"
    echo
    _log_numbered_item 2 "Run the OCI CLI command:"
    _log_info "   oci vault secret create-secret \\"
    _log_info "     --compartment-id <your_compartment_ocid> \\"
    _log_info "     --vault-id <your_vault_ocid> \\"
    _log_info "     --key-id <your_key_ocid> \\"
    _log_info "     --secret-name \"$PROJECT_NAME-config\" \\"
    _log_info "     --secret-content-content <paste_base64_content_here> \\"
    _log_info "     --secret-content-content-type BASE64"
    echo
    _log_numbered_item 3 "Once created, use the new secret OCID with './tools/oci-setup.sh'."
    return 1
}

_update_oci_secret() {
  local settings_file="$1"; local secret_ocid="$2"
  _log_header "Updating OCI Vault Secret"
  [[ -f "$settings_file" ]] || { _log_error "Settings file not found: $settings_file"; return 1; }
  _have_cmd oci || { _log_error "OCI CLI not found"; return 1; }
  oci iam region list >/dev/null 2>&1 || { _log_error "OCI CLI authentication failed"; return 1; }

  local content; content="$(cat "$settings_file")"
  echo "$content" | jq . >/dev/null 2>&1 || { _log_error "Settings file contains invalid JSON"; return 1; }

  if [[ "$DRY_RUN" == "true" ]]; then
    _log_info "[DRY RUN] Would update OCI secret $secret_ocid"
    return 0
  fi

  local encoded; encoded="$(printf '%s' "$content" | base64 -w 0 2>/dev/null || printf '%s' "$content" | base64)"
  _log_info "Updating OCI Vault secret: ${secret_ocid:0:20}..."
  if oci vault secret update \
      --secret-id "$secret_ocid" \
      --secret-content "{\"content\":\"$encoded\", \"contentType\": \"BASE64\"}" >/dev/null 2>&1; then
    _log_success "OCI Vault secret updated successfully"
    return 0
  else
    _log_error "Failed to update OCI Vault secret"
    return 1
  fi
}

_sync_from_oci() {
  local settings_file="$1"; local secret_ocid="$2"
  _log_header "Syncing from OCI Vault"

  if [[ "$CREATE_BACKUP" == "true" && -f "$settings_file" ]]; then
    _backup_file "$settings_file" || _log_warning "Failed to create backup, continuing anyway"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    _log_info "[DRY RUN] Would sync from OCI secret $secret_ocid to $settings_file"
    return 0
  fi

  _log_info "Fetching secret from OCI Vault..."
  local content_b64
  if content_b64="$(oci vault secret get-secret-bundle \
      --secret-id "$secret_ocid" \
      --query 'data."secret-bundle-content".content' \
      --raw-output 2>/dev/null)"; then
    local decoded
    if decoded="$(printf '%s' "$content_b64" | base64 -d 2>/dev/null)"; then
      echo "$decoded" | jq . >/dev/null 2>&1 || { _log_error "Retrieved secret contains invalid JSON"; return 1; }
      printf '%s' "$decoded" > "$settings_file"
      chmod 600 "$settings_file"
      _log_success "Settings synced from OCI Vault successfully"
      return 0
    else
      _log_error "Failed to decode secret content"
      return 1
    fi
  else
    _log_error "Failed to fetch secret from OCI Vault"
    return 1
  fi
}

_generate_tokens_only() {
  _log_header "Generating New Tokens"
  local admin_token backup_passphrase smtp_password
  admin_token="$(_generate_admin_token)"
  backup_passphrase="$(_generate_backup_passphrase)"
  smtp_password="$(_generate_smtp_password)"
  _log_info "Generated Tokens:"
  _log_info " ADMIN_TOKEN: $admin_token"
  _log_info " BACKUP_PASSPHRASE: $backup_passphrase"
  _log_info " SMTP_PASSWORD: $smtp_password"
  echo
  _log_warning "SECURITY NOTE: These tokens are displayed in plaintext"
  _log_warning "Copy them securely and clear your terminal history"
  return 0
}

_main() {
  _have_cmd openssl || { _log_error "openssl command not found. Please install openssl."; exit 1; }
  _have_cmd jq || { _log_error "jq command not found. Please install jq."; exit 1; }

  case "${1:-$ACTION}" in
    rotate-local) _rotate_local_secrets "$SETTINGS_FILE" ;;
    create-oci) _create_oci_secret "$SETTINGS_FILE" ;;
    update-oci)
      : "${OCI_SECRET_OCID:?OCI_SECRET_OCID is required}"
      _update_oci_secret "$SETTINGS_FILE" "$OCI_SECRET_OCID"
      ;;
    sync-from-oci)
      : "${OCI_SECRET_OCID:?OCI_SECRET_OCID is required}"
      _sync_from_oci "$SETTINGS_FILE" "$OCI_SECRET_OCID"
      ;;
    generate-tokens) _generate_tokens_only ;;
    *) _log_error "Unknown action: ${1:-$ACTION}"; _display_usage; exit 1 ;;
  esac
}

_main "$@"