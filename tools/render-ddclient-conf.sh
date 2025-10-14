#!/usr/bin/env bash
# tools/render-ddclient-conf.sh — render ddclient.conf from template and environment on host

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

TEMPLATE="${1:-}"
OUT="${2:-/etc/ddclient.conf}"

# shellcheck source=/dev/null
source "$LIB_DIR/logging.sh"
_set_log_prefix "ddns-render"

# Optional config helpers
# shellcheck source=/dev/null
[[ -f "$LIB_DIR/config.sh" ]] && source "$LIB_DIR/config.sh" || true

[[ -z "$TEMPLATE" ]] && TEMPLATE="$PROJECT_ROOT/templates/ddclient.conf.tmpl" && _log_debug "Using default template: $TEMPLATE"

_validate_template() {
  [[ -f "$TEMPLATE" ]] || { _log_error "Template file not found: $TEMPLATE"; exit 1; }
  [[ -r "$TEMPLATE" ]] || { _log_error "Template file not readable: $TEMPLATE"; exit 1; }
  _log_debug "Template validation passed: $TEMPLATE"
}

_validate_required_vars() {
  local missing=()
  local required=( "DDCLIENT_PROTOCOL" "DDCLIENT_LOGIN" "DDCLIENT_PASSWORD" "DDCLIENT_ZONE" "DDCLIENT_HOST" )
  for v in "${required[@]}"; do
    [[ -n "${!v:-}" ]] || missing+=("$v")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    _log_error "Missing required DDCLIENT variables: ${missing[*]}"
    _log_error "Set them in your environment or settings.json"
    exit 1
  fi
  _log_success "All required DDCLIENT variables are set"
  _log_debug "Protocol: $DDCLIENT_PROTOCOL, Host: $DDCLIENT_HOST, Zone: $DDCLIENT_ZONE"
}

_create_output_dir() {
  local out_dir
  out_dir="$(dirname "$OUT")"
  [[ -d "$out_dir" ]] || { mkdir -p "$out_dir" || { _log_error "Failed to create output directory: $out_dir"; exit 1; }; _log_debug "Created output directory: $out_dir"; }
}

_render_template() {
  _log_info "Rendering DDNS configuration template..."
  if command -v envsubst >/dev/null 2>&1; then
    _log_debug "Using envsubst for template rendering"
    envsubst < "$TEMPLATE" > "$OUT" || { _log_error "envsubst rendering failed"; exit 1; }
  else
    _log_warning "envsubst not available, using manual substitution"
    local content
    content="$(<"$TEMPLATE")"
    content="${content//\$\{DDCLIENT_PROTOCOL\}/$DDCLIENT_PROTOCOL}"
    content="${content//\$\{DDCLIENT_LOGIN\}/$DDCLIENT_LOGIN}"
    content="${content//\$\{DDCLIENT_PASSWORD\}/$DDCLIENT_PASSWORD}"
    content="${content//\$\{DDCLIENT_ZONE\}/$DDCLIENT_ZONE}"
    content="${content//\$\{DDCLIENT_HOST\}/$DDCLIENT_HOST}"
    printf '%s\n' "$content" > "$OUT" || { _log_error "Manual substitution rendering failed"; exit 1; }
  fi
  _log_debug "Template rendering completed successfully"
}

_secure_config_file() {
  chmod 600 "$OUT" || _log_warning "Failed to set restrictive permissions on $OUT"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown root:root "$OUT" 2>/dev/null || _log_warning "Failed to set root ownership on $OUT"
  fi
  _log_debug "Applied security settings to configuration file"
}

_validate_output() {
  [[ -f "$OUT" ]] || { _log_error "Output file was not created: $OUT"; exit 1; }
  [[ -s "$OUT" ]] || { _log_error "Output file is empty: $OUT"; exit 1; }

  local required_keys=("protocol" "login" "password" "zone" "host")
  local missing_keys=()
  for key in "${required_keys[@]}"; do
    grep -q "^$key=" "$OUT" || missing_keys+=("$key")
  done
  if [[ ${#missing_keys[@]} -gt 0 ]]; then
    _log_warning "Generated config may be incomplete. Missing keys: ${missing_keys[*]}"
  else
    _log_debug "Output validation passed - all required keys present"
  fi
}

main() {
  _log_info "DDNS Configuration Renderer Starting"
  _log_debug "Template: $TEMPLATE"
  _log_debug "Output: $OUT"

  _validate_template
  _validate_required_vars
  _create_output_dir
  _render_template
  _secure_config_file
  _validate_output

  _log_success "Successfully rendered ddclient configuration: $OUT"
  _log_info "Protocol: $DDCLIENT_PROTOCOL"
  _log_info "Host: $DDCLIENT_HOST"
  _log_info "Zone: $DDCLIENT_ZONE"
  _log_debug "Configuration file size: $(wc -c < "$OUT") bytes"
}

main "$@"