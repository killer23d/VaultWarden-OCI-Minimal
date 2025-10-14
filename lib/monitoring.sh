#!/usr/bin/env bash
# lib/monitoring.sh — lightweight health checks, self-heal, and alert helpers

set -euo pipefail

# Logging (never print secrets)
_mlog() { printf '[monitor] %s\n' "$*" >&2; }
_merr() { printf '[monitor][error] %s\n' "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || { _merr "Missing command: $1"; return 1; }; }

# Resolve project root (monitor tools always run from repo root or tools/)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. 2>/dev/null || pwd)"

# Source config to get dynamic container names
if [[ -f "$ROOT_DIR/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/config.sh"
    load_config >/dev/null 2>&1 || _merr "Failed to load configuration for container names"
fi

# Source system library for compose helpers
if [[ -f "$ROOT_DIR/lib/system.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/system.sh"
fi

# --- FIX: Dynamic Container Names ---
# Use environment variables for container names, with original names as defaults.
# These can be set in settings.json (e.g., "CONTAINER_NAME_VAULTWARDEN": "my_vw_container")
BW_VW="${CONTAINER_NAME_VAULTWARDEN:-bw_vaultwarden}"
BW_CADDY="${CONTAINER_NAME_CADDY:-bw_caddy}"
BW_FAIL2BAN="${CONTAINER_NAME_FAIL2BAN:-bw_fail2ban}"
# --- END FIX ---

# Email helpers
default_alert_to() {
  # Prefer ALERT_EMAIL_TO, else ADMIN_EMAIL from in-memory config, else empty
  if [ -n "${ALERT_EMAIL_TO:-}" ]; then
    printf '%s' "$ALERT_EMAIL_TO"; return 0
  fi
  if [ -n "${ADMIN_EMAIL:-}" ]; then
    printf '%s' "$ADMIN_EMAIL"; return 0
  fi
  printf ''
}

send_mail() {
  # send_mail "Subject" "Body"
  local subj="$1" body="$2"
  local to; to="$(default_alert_to || true)"
  [ -n "$to" ] || { _merr "No ALERT_EMAIL_TO/ADMIN_EMAIL set; skipping email"; return 0; }

  if command -v mail >/dev/null 2>&1; then
    printf '%s\n' "$body" | mail -s "$subj" "$to" || _merr "mail failed"
    return 0
  fi
  if command -v sendmail >/dev/null 2>&1; then
    {
      printf 'To: %s\n' "$to"
      printf 'Subject: %s\n' "$subj"
      printf 'Content-Type: text/plain; charset=UTF-8\n\n'
      printf '%s\n' "$body"
    } | sendmail -t || _merr "sendmail failed"
    return 0
  fi

  # Fallback: log to file
  mkdir -p "$ROOT_DIR/logs"
  {
    echo "=== EMAIL ALERT (fallback to file) ==="
    echo "To: $to"
    echo "Subject: $subj"
    date -Iseconds
    echo
    echo "$body"
    echo "======================================"
  } >> "$ROOT_DIR/logs/alerts.log"
  _merr "No mail/sendmail available; wrote alert to logs/alerts.log"
}

# Container health checks
is_container_healthy() {
  local name="$1"
  local health
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || echo "none")"
  [ "$health" = "healthy" ]
}

# Stack-level checks
stack_is_healthy() {
  # VaultWarden and Caddy must be healthy; fail2ban just needs to be running if present
  is_container_healthy "$BW_VW" || return 1
  is_container_healthy "$BW_CADDY" || return 1

  # Optionals (ignore if container not present; if present, must be running)
  if docker ps -a --format '{{.Names}}' | grep -qx "$BW_FAIL2BAN"; then
    _compose_service_running "fail2ban" || return 1
  fi
  return 0
}

compose_up() { docker compose up -d || return 1; }
compose_restart() { docker compose restart || return 1; }
compose_reset() {
  docker compose down || true
  docker compose up -d || return 1
}

# Self-heal strategy: up -> restart -> reset (down+up), with waits and re-checks
self_heal_once() {
  local wait="${1:-15}"
  _mlog "Self-heal step 1: compose up -d"
  compose_up || _merr "compose up failed"
  sleep "$wait"
  stack_is_healthy && return 0

  _mlog "Self-heal step 2: compose restart"
  compose_restart || _merr "compose restart failed"
  sleep "$wait"
  stack_is_healthy && return

}