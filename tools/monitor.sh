#!/usr/bin/env bash
# tools/monitor.sh - Enhanced health check and self-heal for the stack with database maintenance
#
# This script provides comprehensive system monitoring including:
# - Stack health monitoring and self-healing
# - Automated database maintenance scheduling
# - Alert notifications and logging
# - Integration with the existing library ecosystem
#
# Dependencies: lib/logging.sh, lib/monitoring.sh, lib/config.sh
#

set -euo pipefail

# Auto-detect script location and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source libraries first to get logging and config
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/monitoring.sh"
source "$ROOT_DIR/lib/system.sh"

# Set logging prefix
_set_log_prefix "monitor"

# Configuration constants, using paths from config.sh
readonly LOG_DIR="$PROJECT_STATE_DIR/logs"
readonly LOCKFILE="$LOG_DIR/monitor.lock"
readonly SNAPSHOT="$LOG_DIR/monitor-snapshot.txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# --- Main Execution with Flock ---
# Use flock to ensure only one instance of the script runs at a time.
# The lock is automatically released when the script exits.
(
  flock -n 9 || { _log_warning "Another monitor run is active, exiting."; exit 0; }

  # Load configuration with error handling
  if ! load_config 2>/dev/null; then
      _log_warning "Could not load configuration, using defaults"
  fi

  # Validate prerequisites
  if ! _have_cmd docker; then
      _log_error "Docker not available - cannot perform monitoring"
      exit 1
  fi

  # Execute main monitoring workflow
  if _main_monitor_workflow; then
      _log_info "Monitoring cycle completed successfully"
      exit 0
  else
      _log_error "Monitoring cycle completed with issues"
      exit 1
  fi

) 9>"$LOCKFILE"


# Database maintenance integration functions
_run_database_maintenance() {
    local maintenance_type="$1"
    local sqlite_maintenance_script="$ROOT_DIR/tools/sqlite-maintenance.sh"

    if [[ ! -f "$sqlite_maintenance_script" ]]; then
        _log_debug "sqlite-maintenance.sh not found, skipping database maintenance"
        return 0
    fi

    if [[ ! -x "$sqlite_maintenance_script" ]]; then
        _log_warning "Making sqlite-maintenance.sh executable"
        chmod +x "$sqlite_maintenance_script"
    fi

    _log_info "Running database maintenance: $maintenance_type"

    local start_time; start_time=$(date +%s)
    local result="success"

    if "$sqlite_maintenance_script" -t "$maintenance_type"; then
        local end_time; end_time=$(date +%s)
        local duration=$((end_time - start_time))
        _log_info "Database maintenance ($maintenance_type) completed successfully in ${duration}s"
    else
        local end_time; end_time=$(date +%s)
        local duration=$((end_time - start_time))
        _log_error "Database maintenance ($maintenance_type) failed after ${duration}s"
        result="failed"

        # Send alert for database maintenance failures
        local subject="Database Maintenance Failed on $(hostname -s)"
        local body="Database maintenance ($maintenance_type) failed on $(hostname -f 2>/dev/null || hostname -s) at $(date)"
        send_mail "$subject" "$body" 2>/dev/null || true

        return 1
    fi
}

# Scheduled database maintenance based on current date/time
_check_scheduled_maintenance() {
    local current_day_of_week; current_day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    local current_hour; current_hour=$(date +%H)
    local current_minute; current_minute=$(date +%M)

    # Weekly full maintenance: Monday at 2:00 AM
    if [[ "$current_day_of_week" -eq 1 ]] && [[ "$current_hour" -eq 2 ]] && [[ "$current_minute" -lt 10 ]]; then
        _log_info "Scheduled weekly database maintenance starting"
        _run_database_maintenance "full"
        return $?
    fi

    # Daily quick check: Every day at 6:00 AM (except Monday which runs full maintenance)
    if [[ "$current_day_of_week" -ne 1 ]] && [[ "$current_hour" -eq 6 ]] && [[ "$current_minute" -lt 10 ]]; then
        _log_info "Scheduled daily database maintenance starting"
        _run_database_maintenance "quick"
        return $?
    fi

    # Optional: Quick integrity check every 6 hours
    if [[ "$current_hour" -eq 9 || "$current_hour" -eq 15 || "$current_hour" -eq 21 ]] && [[ "$current_minute" -lt 5 ]]; then
        _log_debug "Running periodic integrity check"
        _run_database_maintenance "integrity"
        return 0
    fi

    return 0
}

# Enhanced health check with database validation
_enhanced_health_check() {
    local health_issues=0

    # Standard stack health check
    if ! stack_is_healthy; then
        _log_warning "Stack health check failed"
        ((health_issues++))
    fi

    # Database connectivity check
    if _have_cmd sqlite3; then
        # Path is dynamically determined by lib/config.sh and used by sqlite-maintenance.sh
        _log_debug "Checking database connectivity..."
        if ! "$ROOT_DIR/tools/sqlite-maintenance.sh" -t integrity >/dev/null 2>&1; then
             _log_warning "Database connectivity or integrity check failed."
             ((health_issues++))
        else
            _log_debug "Database connectivity and integrity check passed."
        fi
    fi

    # Disk space check (warn if less than 1GB free)
    local available_space
    available_space=$(df "$ROOT_DIR" | tail -1 | awk '{print $4}' || echo "0")
    if [[ "$available_space" -lt 1048576 ]]; then  # Less than 1GB in KB
        _log_warning "Low disk space detected ($(( available_space / 1024 ))MB available)"
    fi

    return $health_issues
}

# Main monitoring function with database integration
_main_monitor_workflow() {
    _log_info "Starting monitoring cycle (PID: $$)"

    # Run scheduled database maintenance first
    _check_scheduled_maintenance || {
        _log_warning "Scheduled maintenance encountered issues, continuing with health monitoring"
    }

    # Enhanced health check
    local health_status; health_status=$(_enhanced_health_check)
    if [[ $health_status -eq 0 ]]; then
        _log_info "System health check passed"
        _cleanup_old_files
        return 0
    fi

    _log_warning "System health check failed, initiating self-healing"

    # Self-healing attempts
    local attempts="${ATTEMPTS:-3}"
    local sleep_between="${SLEEP_BETWEEN:-20}"

    for ((i=1; i<=attempts; i++)); do
        _log_info "Self-heal attempt $i of $attempts"

        if self_heal_once "$sleep_between"; then
            _log_success "Self-heal successful on attempt $i"
            _run_database_maintenance "integrity" || _log_warning "Post-healing database check failed, but continuing"
            return 0
        fi

        if [[ $i -lt $attempts ]]; then
            _log_warning "Self-heal attempt $i failed, waiting before retry..."
            sleep "$sleep_between"
        fi
    done

    _log_error "Self-heal failed after $attempts attempts, collecting diagnostics"

    # Use monitoring library's snapshot function if available
    if command -v collect_status_snapshot >/dev/null 2>&1; then
        collect_status_snapshot "$SNAPSHOT" || _log_error "Failed to collect status snapshot"
    fi

    # Send comprehensive alert
    local subject="$PROJECT_NAME stack unrecoverable on $(hostname -s)"
    local body; body="$(printf 'Project: %s\nTime: %s\nHost: %s\nAttempts: %d\n\nDiagnostic Info attached.' \
        "$PROJECT_NAME" \
        "$(date -Iseconds)" \
        "$(hostname -f 2>/dev/null || hostname -s)" \
        "$attempts")"

    send_mail "$subject" "$body" || _log_error "Failed to send failure notification"

    return 1
}

# Cleanup function for maintenance
_cleanup_old_files() {
    # Clean up old log files (keep last 30 days)
    find "$LOG_DIR" -name "*.log.*" -type f -mtime +30 -delete 2>/dev/null || true

    # Clean up old backup files from maintenance (keep last 10)
    find "$PROJECT_STATE_DIR/data/bwdata" -name "*.maintenance-backup.*" -type f | \
        sort -r | tail -n +11 | xargs -r rm -f 2>/dev/null || true

    _log_debug "Cleanup completed"
}