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
# Author: VaultWarden OCI Minimal Project
# License: MIT
#

set -euo pipefail

# Auto-detect script location and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="$(basename "$ROOT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"

LIB_DIR="$ROOT_DIR/lib"
LOG_DIR="$ROOT_DIR/logs"
LOCKFILE="$LOG_DIR/monitor.lock"
SNAPSHOT="$LOG_DIR/monitor-snapshot.txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions with timestamp
log() { printf '[%s][monitor] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_DIR/monitor.log" >&2; }
err() { printf '[%s][monitor][error] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_DIR/monitor.log" >&2; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && printf '[%s][monitor][debug] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_DIR/monitor.log" >&2 || true; }

# Load required libraries
if [[ -f "$LIB_DIR/config.sh" ]]; then
    source "$LIB_DIR/config.sh"
    load_config 2>/dev/null || {
        log "Warning: Could not load configuration, using defaults"
    }
else
    log "Warning: lib/config.sh not found, using basic configuration"
fi

if [[ -f "$LIB_DIR/monitoring.sh" ]]; then
    source "$LIB_DIR/monitoring.sh"
else
    log "Warning: lib/monitoring.sh not found, using basic monitoring functions"

    # Basic monitoring functions if library not available
    stack_is_healthy() {
        docker compose -f "$ROOT_DIR/docker-compose.yml" ps --format json 2>/dev/null | \
        jq -r '.[] | select(.Service=="vaultwarden") | .Health' 2>/dev/null | grep -q "healthy"
    }

    self_heal_once() {
        local sleep_time="${1:-20}"
        log "Attempting self-heal by restarting unhealthy services"

        if ! docker compose -f "$ROOT_DIR/docker-compose.yml" restart; then
            log "Failed to restart services"
            return 1
        fi

        sleep "$sleep_time"

        if stack_is_healthy; then
            log "Self-heal successful"
            return 0
        else
            log "Self-heal attempt failed"
            return 1
        fi
    }

    collect_status_snapshot() {
        local snapshot_file="$1"
        {
            echo "=== Docker Compose Status ==="
            docker compose -f "$ROOT_DIR/docker-compose.yml" ps 2>/dev/null || echo "Failed to get compose status"

            echo -e "\n=== Container Logs (last 50 lines) ==="
            docker compose -f "$ROOT_DIR/docker-compose.yml" logs --tail=50 2>/dev/null || echo "Failed to get logs"

            echo -e "\n=== System Resources ==="
            df -h 2>/dev/null || echo "Failed to get disk usage"
            free -h 2>/dev/null || echo "Failed to get memory usage"

            echo -e "\n=== Network Status ==="
            ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null || echo "Failed to get network status"
        } > "$snapshot_file"
    }

    send_mail() {
        local subject="$1"
        local body="$2"
        local email="${ADMIN_EMAIL:-root@localhost}"

        if command -v mail >/dev/null 2>&1; then
            echo "$body" | mail -s "$subject" "$email" 2>/dev/null || {
                log "Failed to send email notification"
                return 1
            }
        else
            log "Mail command not available, cannot send notification"
            return 1
        fi
    }

    need() {
        command -v "$1" >/dev/null 2>&1
    }
fi

# Database maintenance integration functions
_run_database_maintenance() {
    local maintenance_type="$1"
    local sqlite_maintenance_script="$ROOT_DIR/tools/sqlite-maintenance.sh"

    if [[ ! -f "$sqlite_maintenance_script" ]]; then
        debug "sqlite-maintenance.sh not found, skipping database maintenance"
        return 0
    fi

    if [[ ! -x "$sqlite_maintenance_script" ]]; then
        log "Making sqlite-maintenance.sh executable"
        chmod +x "$sqlite_maintenance_script"
    fi

    log "Running database maintenance: $maintenance_type"

    local start_time=$(date +%s)
    local result="success"

    if "$sqlite_maintenance_script" -t "$maintenance_type" 2>&1 | tee -a "$LOG_DIR/monitor.log"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "Database maintenance ($maintenance_type) completed successfully in ${duration}s"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        err "Database maintenance ($maintenance_type) failed after ${duration}s"
        result="failed"

        # Send alert for database maintenance failures
        local subject="Database Maintenance Failed on $(hostname -s)"
        local body="Database maintenance ($maintenance_type) failed on $(hostname -f 2>/dev/null || hostname -s) at $(date)\n\nCheck logs: $LOG_DIR/monitor.log"
        send_mail "$subject" "$body" 2>/dev/null || true

        return 1
    fi
}

# Scheduled database maintenance based on current date/time
_check_scheduled_maintenance() {
    local current_day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    local current_hour=$(date +%H)
    local current_minute=$(date +%M)

    # Weekly full maintenance: Monday at 2:00 AM
    if [[ "$current_day_of_week" -eq 1 ]] && [[ "$current_hour" -eq 2 ]] && [[ "$current_minute" -lt 10 ]]; then
        log "Scheduled weekly database maintenance starting"
        _run_database_maintenance "full"
        return $?
    fi

    # Daily quick check: Every day at 6:00 AM (except Monday which runs full maintenance)
    if [[ "$current_day_of_week" -ne 1 ]] && [[ "$current_hour" -eq 6 ]] && [[ "$current_minute" -lt 10 ]]; then
        log "Scheduled daily database maintenance starting"
        _run_database_maintenance "quick"
        return $?
    fi

    # Optional: Quick integrity check every 6 hours during business hours (9 AM, 3 PM, 9 PM)
    if [[ "$current_hour" -eq 9 || "$current_hour" -eq 15 || "$current_hour" -eq 21 ]] && [[ "$current_minute" -lt 5 ]]; then
        debug "Running periodic integrity check"
        _run_database_maintenance "integrity"
        # Don't fail monitoring if integrity check fails (non-critical)
        return 0
    fi

    return 0
}

# Enhanced health check with database validation
_enhanced_health_check() {
    local health_issues=0

    # Standard stack health check
    if ! stack_is_healthy; then
        log "Stack health check failed"
        ((health_issues++))
    fi

    # Database connectivity check
    if command -v sqlite3 >/dev/null 2>&1; then
        local db_paths=(
            "/var/lib/${PROJECT_NAME}/data/bwdata/db.sqlite3"
            "$ROOT_DIR/data/bwdata/db.sqlite3"
        )

        local db_found=false
        for db_path in "${db_paths[@]}"; do
            if [[ -f "$db_path" ]]; then
                debug "Checking database connectivity: $db_path"

                # Quick database connectivity test
                if timeout 10 sqlite3 "$db_path" "SELECT 1;" >/dev/null 2>&1; then
                    debug "Database connectivity check passed"
                    db_found=true
                    break
                else
                    log "Database connectivity check failed: $db_path"
                    ((health_issues++))
                fi
            fi
        done

        if [[ "$db_found" == "false" ]]; then
            log "No accessible database found for health check"
            ((health_issues++))
        fi
    fi

    # Check for maintenance failure indicators
    if [[ -f "/tmp/sqlite-maintenance-status" ]]; then
        local maintenance_status
        maintenance_status=$(cat "/tmp/sqlite-maintenance-status" 2>/dev/null || echo "")

        if [[ "$maintenance_status" =~ SQLITE_MAINTENANCE_FAILED ]]; then
            log "Previous database maintenance failure detected"
            ((health_issues++))

            # Clear the status after detection
            rm -f "/tmp/sqlite-maintenance-status" 2>/dev/null || true
        fi
    fi

    # Disk space check (warn if less than 1GB free)
    local available_space
    available_space=$(df "$ROOT_DIR" | tail -1 | awk '{print $4}' || echo "0")
    if [[ "$available_space" -lt 1048576 ]]; then  # Less than 1GB in KB
        log "Warning: Low disk space detected ($(( available_space / 1024 ))MB available)"
        # Don't fail health check for low disk space, just warn
    fi

    return $health_issues
}

# Main monitoring function with database integration
_main_monitor_workflow() {
    log "Starting monitoring cycle (PID: $$)"

    # Run scheduled database maintenance first
    _check_scheduled_maintenance || {
        log "Scheduled maintenance encountered issues, continuing with health monitoring"
    }

    # Enhanced health check
    if _enhanced_health_check; then
        log "System health check passed"

        # Cleanup old logs and maintenance artifacts
        _cleanup_old_files

        return 0
    fi

    log "System health check failed, initiating self-healing"

    # Self-healing attempts
    local attempts="${ATTEMPTS:-3}"
    local sleep_between="${SLEEP_BETWEEN:-20}"

    for ((i=1; i<=attempts; i++)); do
        log "Self-heal attempt $i of $attempts"

        if self_heal_once "$sleep_between"; then
            log "Self-heal successful on attempt $i"

            # Run a quick database integrity check after successful healing
            _run_database_maintenance "integrity" || {
                log "Post-healing database check failed, but continuing"
            }

            return 0
        fi

        if [[ $i -lt $attempts ]]; then
            log "Self-heal attempt $i failed, waiting before retry..."
            sleep "$sleep_between"
        fi
    done

    # Self-healing failed - collect comprehensive diagnostics
    log "Self-heal failed after $attempts attempts, collecting diagnostics"

    collect_status_snapshot "$SNAPSHOT" || {
        log "Failed to collect status snapshot"
    }

    # Enhanced diagnostic information
    {
        echo -e "\n=== Database Status ==="
        _run_database_maintenance "integrity" --dry-run 2>&1 || echo "Database diagnostics failed"

        echo -e "\n=== Recent Monitor Log ==="
        tail -50 "$LOG_DIR/monitor.log" 2>/dev/null || echo "Monitor log unavailable"

        echo -e "\n=== System Information ==="
        uname -a 2>/dev/null || echo "System info unavailable"
        uptime 2>/dev/null || echo "Uptime unavailable"

    } >> "$SNAPSHOT"

    # Send comprehensive alert
    local subject="$PROJECT_NAME stack unrecoverable on $(hostname -s)"
    local body="$(printf 'Project: %s\nTime: %s\nHost: %s\nAttempts: %d\n\nDiagnostic Information:\n\n%s\n' \
        "$PROJECT_NAME" \
        "$(date -Iseconds)" \
        "$(hostname -f 2>/dev/null || hostname -s)" \
        "$attempts" \
        "$(tail -1000 "$SNAPSHOT" 2>/dev/null || echo '(diagnostic data unavailable)')")"

    send_mail "$subject" "$body" || {
        log "Failed to send failure notification"
    }

    return 1
}

# Cleanup function for maintenance
_cleanup_old_files() {
    # Clean up old log files (keep last 30 days)
    find "$LOG_DIR" -name "*.log.*" -type f -mtime +30 -delete 2>/dev/null || true

    # Clean up old backup files from maintenance (keep last 10)
    find "$ROOT_DIR/data/bwdata" -name "*.maintenance-backup.*" -type f | \
        sort -r | tail -n +11 | xargs -r rm -f 2>/dev/null || true

    # Clean up temporary files
    find /tmp -name "sqlite-maintenance-*" -type f -mtime +1 -delete 2>/dev/null || true

    debug "Cleanup completed"
}

# Prevent overlapping monitor runs
if [[ -f "$LOCKFILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")

    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        log "Another monitor run (PID: $existing_pid) is active, exiting"
        exit 0
    else
        log "Stale lockfile detected, removing"
        rm -f "$LOCKFILE"
    fi
fi

echo "$$" > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Validate prerequisites
need docker || { 
    err "Docker not available - cannot perform monitoring"
    exit 1
}

# Execute main monitoring workflow
if _main_monitor_workflow; then
    log "Monitoring cycle completed successfully"
    exit 0
else
    log "Monitoring cycle completed with issues"
    exit 1
fi
