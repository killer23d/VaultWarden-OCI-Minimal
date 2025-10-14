#!/usr/bin/env bash
# tools/db-backup.sh — Enhanced SQLite backup with WAL-awareness, resource management, and multi-format support

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$ROOT_DIR/lib"

# Load libraries in dependency order
# shellcheck source=/dev/null
source "$LIB_DIR/logging.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/config.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/backup-core.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/backup-formats.sh"

# Load configuration into memory
load_config

# Set log prefix for this script
_set_log_prefix "db-backup"

# --- FIX: New function to get DB path from config ---
_detect_database_path() {
    if [[ -n "${DB_FILE:-}" ]]; then
        _log_debug "Using pre-set database path: $DB_FILE"
        return 0
    fi

    local db_url
    db_url=$(get_config_value "DATABASE_URL")

    if [[ -z "$db_url" ]]; then
        _log_error "DATABASE_URL not found in configuration."
        return 1
    fi

    if [[ "$db_url" =~ ^sqlite://(.+) ]]; then
        local relative_path="${BASH_REMATCH[1]}"
        if [[ "$relative_path" != /* ]]; then
            DB_FILE="$ROOT_DIR/$relative_path"
        else
            DB_FILE="$relative_path"
        fi
        _log_info "Detected database path from config: $DB_FILE"
    else
        _log_error "Unsupported DATABASE_URL format: $db_url"
        return 1
    fi

    return 0
}

init_enhanced_backup() {
    _log_info "Initializing enhanced database backup system"
    init_backup_core

    : "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required in settings}"

    _detect_database_path || exit 1
    
    [[ -f "$DB_FILE" ]] || { _log_error "SQLite database not found at $DB_FILE"; exit 1; }

    TS="$(date +%Y%m%d-%H%M%S)"
    OUT_DIR="${BACKUP_DIR:-$PROJECT_STATE_DIR/backups/db}/$TS"
    mkdir -p "$OUT_DIR"

    _log_success "Backup initialized - Output: $OUT_DIR"
    _log_info "Database: $(du -h "$DB_FILE" | cut -f1) ($(basename "$DB_FILE"))"
}

perform_enhanced_backup() {
    _log_info "Starting enhanced database backup process"

    check_system_resources "$DB_FILE" "$OUT_DIR"

    if ! create_diverse_backups "$DB_FILE" "$OUT_DIR" "$TS"; then
        _log_error "Backup creation failed"
        exit 1
    fi

    _log_info "Compressing and encrypting backup files"

    local encrypted_files=()
    local failures=()

    # Process regular files in OUT_DIR
    while IFS= read -r -d '' backup_file; do
        if [[ -f "$backup_file" && "$backup_file" != */manifest.json ]]; then
            local base_name compressed_file encrypted_file
            base_name="$(basename "$backup_file")"
            _log_debug "Processing: $base_name"

            compressed_file="${backup_file}.gz"
            if compress_with_resource_limits "$backup_file" "$compressed_file"; then
                encrypted_file="${compressed_file}.gpg"
                if encrypt_backup_file "$compressed_file" "$BACKUP_PASSPHRASE" "$encrypted_file"; then
                    encrypted_files+=("$encrypted_file")
                    _log_success "✓ Processed: $base_name → $(basename "$encrypted_file")"
                else
                    failures+=("$base_name (encryption)")
                    _log_error "✗ Encryption failed: $base_name"
                fi
            else
                failures+=("$base_name (compression)")
                _log_error "✗ Compression failed: $base_name"
            fi
        fi
    done < <(find "$OUT_DIR" -maxdepth 1 -type f -print0)

    # CSV exports directory
    local csv_dir="$OUT_DIR/csv-exports"
    if [[ -d "$csv_dir" ]]; then
        _log_debug "Compressing CSV exports directory"
        local csv_archive="$OUT_DIR/csv-exports-$TS.tar.gz"
        if tar -C "$OUT_DIR" -czf "$csv_archive" "csv-exports/"; then
            local csv_encrypted="${csv_archive}.gpg"
            if encrypt_backup_file "$csv_archive" "$BACKUP_PASSPHRASE" "$csv_encrypted"; then
                encrypted_files+=("$csv_encrypted")
                rm -rf "$csv_dir"
                _log_success "✓ Processed: csv-exports → $(basename "$csv_encrypted")"
            else
                failures+=("csv-exports (encryption)")
                _log_error "✗ CSV exports encryption failed"
            fi
        else
            failures+=("csv-exports (compression)")
            _log_error "✗ CSV exports compression failed"
        fi
    fi

    [[ ${#encrypted_files[@]} -gt 0 ]] && _log_info "Successfully encrypted ${#encrypted_files[@]} backup files"
    [[ ${#failures[@]} -gt 0 ]] && _log_warning "Some files failed processing: ${failures[*]}"
}

verify_enhanced_backups() {
    _log_info "Performing comprehensive backup verification"

    local verification_passed=true
    local temp_dir
    temp_dir="$(mktemp -d -p "$OUT_DIR" verify.XXXXXX)"

    # Binary backup
    local binary_encrypted
    binary_encrypted="$(find "$OUT_DIR" -name "db-native-*.sqlite3.gz.gpg" | head -n1 || true)"
    if [[ -n "$binary_encrypted" ]]; then
        _log_debug "Verifying encrypted binary backup"
        local temp_bin pass_file temp_db
        temp_bin="$(mktemp -p "$temp_dir" verify-bin.XXXXXX.sqlite3.gz)"
        pass_file="$(mktemp -p "$temp_dir" pass.XXXXXX)"
        chmod 600 "$pass_file"
        printf "%s" "$BACKUP_PASSPHRASE" > "$pass_file"
        if gpg --batch --yes --quiet --passphrase-file "$pass_file" -o "$temp_bin" -d "$binary_encrypted"; then
            gunzip -f "$temp_bin"
            temp_db="${temp_bin%.gz}"
            if verify_backup_integrity "$temp_db" "$DB_FILE"; then
                _log_success "✓ Binary backup verification passed"
            else
                _log_error "✗ Binary backup verification failed"
                verification_passed=false
            fi
            shred -u "$temp_db" 2>/dev/null || rm -f "$temp_db"
        else
            _log_error "✗ Binary backup decryption failed during verification"
            verification_passed=false
        fi
        shred -u "$pass_file" 2>/dev/null || rm -f "$pass_file"
    fi

    # SQL dump
    local sql_encrypted
    sql_encrypted="$(find "$OUT_DIR" -name "db-portable-*.sql.gz.gpg" | head -n1 || true)"
    if [[ -n "$sql_encrypted" ]]; then
        _log_debug "Verifying encrypted SQL dump backup"
        local temp_sql pass_file_sql temp_sql_file test_db
        temp_sql="$(mktemp -p "$temp_dir" verify-sql.XXXXXX.sql.gz)"
        pass_file_sql="$(mktemp -p "$temp_dir" pass.XXXXXX)"
        chmod 600 "$pass_file_sql"
        printf "%s" "$BACKUP_PASSPHRASE" > "$pass_file_sql"
        if gpg --batch --yes --quiet --passphrase-file "$pass_file_sql" -o "$temp_sql" -d "$sql_encrypted"; then
            gunzip -f "$temp_sql"
            temp_sql_file="${temp_sql%.gz}"
            test_db="$(mktemp -p "$temp_dir" test-restore.XXXXXX.sqlite3)"
            if sqlite3 "$test_db" < "$temp_sql_file" 2>/dev/null && sqlite3 "$test_db" "PRAGMA integrity_check;" | grep -q '^ok$'; then
                _log_success "✓ SQL dump backup verification passed"
            else
                _log_error "✗ SQL dump backup verification failed"
                verification_passed=false
            fi
            rm -f "$test_db" "$temp_sql_file"
        else
            _log_error "✗ SQL dump backup decryption failed during verification"
            verification_passed=false
        fi
        shred -u "$pass_file_sql" 2>/dev/null || rm -f "$pass_file_sql"
    fi

    rm -rf "$temp_dir"

    if $verification_passed; then
        _log_info "All backup verifications passed"
        return 0
    else
        _log_warning "Some backup verifications failed"
        return 1
    fi
}

upload_backups_to_cloud() {
    if [[ -n "${RCLONE_REMOTE:-}" && -n "${RCLONE_PATH:-}" && -x "$(command -v rclone || true)" ]]; then
        _log_info "Uploading backups to cloud storage: $RCLONE_REMOTE:$RCLONE_PATH"
        local upload_path="$RCLONE_REMOTE:$RCLONE_PATH/$TS"
        if rclone copy "$OUT_DIR" "$upload_path" --transfers=4 --checkers=4 --progress --exclude="verify.*" --exclude="*.tmp" 2>/dev/null; then
            _log_success "Cloud upload completed successfully"
            local local_files remote_files
            local_files="$(find "$OUT_DIR" -name "*.gpg" | wc -l)"
            remote_files="$(rclone lsf "$upload_path" --files-only | grep -c '\.gpg$' || echo "0")"
            if [[ "$local_files" -eq "$remote_files" ]]; then
                _log_success "Cloud upload verification passed ($remote_files files)"
            else
                _log_warning "Cloud upload verification failed (local: $local_files, remote: $remote_files)"
            fi
        else
            _log_error "Cloud upload failed"
            return 1
        fi
    else
        _log_debug "Cloud storage not configured, skipping upload"
    fi
}

manage_backup_retention() {
    local backup_base_dir
    backup_base_dir="$(dirname "$OUT_DIR")"
    local keep="${BACKUP_KEEP_DB:-30}"
    if [[ "$keep" -gt 0 ]]; then
        _log_info "Managing local backup retention (keeping $keep recent backups)"
        local current_count
        current_count="$(find "$backup_base_dir" -maxdepth 1 -type d -name '20*' | wc -l)"
        if [[ "$current_count" -gt "$keep" ]]; then
            local to_remove=$((current_count - keep))
            _log_info "Removing $to_remove old backup(s) to maintain retention policy"
            find "$backup_base_dir" -maxdepth 1 -type d -name '20*' | sort | head -n "$to_remove" | xargs -r rm -rf
        fi
        current_count="$(find "$backup_base_dir" -maxdepth 1 -type d -name '20*' | wc -l)"
        _log_info "Local backup retention: $current_count backup directories"
    fi
}

main() {
    local start_time end_time duration
    start_time="$(date +%s)"
    _log_header "VaultWarden Enhanced Database Backup"

    init_enhanced_backup
    perform_enhanced_backup

    if ! verify_enhanced_backups; then
        _log_warning "Backup verification had issues, but backups were created"
    fi

    upload_backups_to_cloud || _log_warning "Cloud upload failed, but local backup completed"
    manage_backup_retention

    end_time="$(date +%s)"
    duration=$((end_time - start_time))
    _log_header "Backup Complete"
    _log_info "Duration: ${duration}s | Output: $OUT_DIR"
    _log_info "Formats: Binary SQLite, Portable SQL, JSON, CSV, Schema"

    local total_size
    total_size="$(du -sh "$OUT_DIR" | cut -f1)"
    _log_info "Total backup size: $total_size"

    local encrypted_count
    encrypted_count="$(find "$OUT_DIR" -name "*.gpg" | wc -l)"
    _log_info "Encrypted files created: $encrypted_count"
}

main "$@"