#!/usr/bin/env bash
# lib/backup-formats.sh — multi-format backup creation with cross-platform compatibility

set -euo pipefail

# Source backup core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/backup-core.sh"

# Internal logging functions
_format_log() { printf "[backup-formats] %s\n" "$*" >&2; }
_format_info() { printf "[backup-formats] ${GREEN}%s${NC}\n" "$*" >&2; }
_format_warn() { printf "[backup-formats] ${YELLOW}%s${NC}\n" "$*" >&2; }
_format_error() { printf "[backup-formats][error] ${RED}%s${NC}\n" "$*" >&2; }
_format_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[backup-formats][debug] ${CYAN}%s${NC}\n" "$*" >&2 || true; }

# Create binary SQLite backup with transaction safety
create_binary_backup() {
  local db_file="${1:?Database file required}"
  local output_file="${2:?Output file required}"
  local timeout="${3:-60}"
  
  _format_debug "Creating binary SQLite backup"
  
  # Use transaction isolation for consistency
  sqlite3 "$db_file" <<EOF || return 1
.timeout $timeout
BEGIN IMMEDIATE;
.backup '$output_file'
COMMIT;
EOF
  
  _format_info "Binary backup created: $(basename "$output_file")"
}

# Create portable SQL dump with compatibility headers
create_portable_sql_dump() {
  local db_file="${1:?Database file required}"
  local output_file="${2:?Output file required}"
  local timeout="${3:-60}"
  
  _format_debug "Creating portable SQL dump with compatibility headers"
  
  # Create header with metadata for cross-platform compatibility
  cat > "$output_file" << EOF
-- VaultWarden Database Backup (Portable SQL Format)
-- Created: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
-- SQLite Version: $(sqlite3 --version 2>/dev/null || echo "unknown")
-- Database Size: $(du -h "$db_file" 2>/dev/null | cut -f1 || echo "unknown")
-- Generator: VaultWarden-OCI-Minimal Enhanced Backup System
-- 
-- This dump is designed for maximum cross-platform compatibility
-- Compatible with SQLite 3.8.0+ (released 2013-08-26)
-- Restore: sqlite3 database.db < thisfile.sql
--
PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

EOF
  
  # Create the actual dump with transaction safety
  sqlite3 "$db_file" <<EOF >> "$output_file" || return 1
.timeout $timeout
-- Ensure consistent output format
.mode insert
.headers off
-- Begin transaction-safe dump
BEGIN DEFERRED;
.dump
COMMIT;
EOF
  
  # Add footer
  cat >> "$output_file" << EOF

-- End of dump
COMMIT;
PRAGMA foreign_keys=ON;
-- Restore complete. Run 'PRAGMA integrity_check;' to verify.
EOF
  
  _format_info "Portable SQL dump created: $(basename "$output_file")"
}

# Create CSV exports for critical tables
create_csv_exports() {
  local db_file="${1:?Database file required}"
  local output_dir="${2:?Output directory required}"
  local timestamp="${3:?Timestamp required}"
  
  _format_debug "Creating CSV exports for critical tables"
  
  local csv_dir="$output_dir/csv-exports"
  mkdir -p "$csv_dir"
  
  # Get list of user tables (exclude SQLite system tables)
  local tables_file
  tables_file=$(mktemp -p "${TMPDIR:-/tmp}" tables.XXXXXX)
  sqlite3 "$db_file" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" > "$tables_file"
  
  local table_count=0
  local exported_tables=()
  
  while IFS= read -r table; do
    if [ -n "$table" ]; then
      _format_debug "Exporting table to CSV: $table"
      
      # Get row count for progress indication
      local row_count
      row_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "0")
      
      if [ "$row_count" -gt 0 ]; then
        # Export table data to CSV
        sqlite3 "$db_file" <<EOF > "$csv_dir/${table}-${timestamp}.csv" || continue
.mode csv
.headers on
.timeout 30
SELECT * FROM "$table";
EOF
        exported_tables+=("$table")
        table_count=$((table_count + 1))
        _format_debug "Exported $table: $row_count rows"
      else
        _format_debug "Skipping empty table: $table"
      fi
    fi
  done < "$tables_file"
  
  rm -f "$tables_file"
  
  # Create manifest file with export metadata
  cat > "$csv_dir/manifest.json" <<EOF
{
  "export_metadata": {
    "created": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
    "database_file": "$(basename "$db_file")",
    "database_size": "$(du -h "$db_file" 2>/dev/null | cut -f1 || echo "unknown")",
    "sqlite_version": "$(sqlite3 --version 2>/dev/null || echo "unknown")",
    "export_format": "csv",
    "tables_exported": $table_count,
    "export_timestamp": "$timestamp"
  },
  "tables": [
$(printf '    "%s"' "${exported_tables[@]}" | paste -sd ',' | sed 's/,/,\n/g')
  ],
  "usage": {
    "description": "CSV exports for manual data recovery and analysis",
    "import_note": "These files can be imported into any spreadsheet application or database system",
    "encoding": "UTF-8"
  }
}
EOF
  
  _format_info "CSV exports completed: $table_count tables exported to $(basename "$csv_dir")"
}

# Create JSON export for modern compatibility
create_json_export() {
  local db_file="${1:?Database file required}"
  local output_file="${2:?Output file required}"
  local timeout="${3:-60}"
  
  _format_debug "Creating structured JSON export"
  
  # Create structured JSON export with metadata
  cat > "$output_file" << EOF
{
  "database_export": {
    "metadata": {
      "created": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
      "generator": "VaultWarden-OCI-Minimal Enhanced Backup",
      "format_version": "1.0",
      "sqlite_version": "$(sqlite3 --version 2>/dev/null || echo "unknown")",
      "database_size": "$(du -h "$db_file" 2>/dev/null | cut -f1 || echo "unknown")",
      "compression": "none",
      "encoding": "UTF-8"
    },
    "schema": {
EOF
  
  # Export schema information
  sqlite3 "$db_file" "SELECT json_group_array(json_object('name', name, 'type', type, 'sql', sql)) FROM sqlite_master WHERE type IN ('table', 'index', 'view') AND name NOT LIKE 'sqlite_%';" | \
    jq '.[0] // []' >> "$output_file" 2>/dev/null || echo "[]" >> "$output_file"
  
  echo '    },' >> "$output_file"
  echo '    "data": {' >> "$output_file"
  
  # Export table data as JSON objects
  local first_table=true
  local tables_file
  tables_file=$(mktemp -p "${TMPDIR:-/tmp}" json-tables.XXXXXX)
  sqlite3 "$db_file" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" > "$tables_file"
  
  while IFS= read -r table; do
    if [ -n "$table" ]; then
      _format_debug "Exporting table to JSON: $table"
      
      if [ "$first_table" = false ]; then
        echo "," >> "$output_file"
      fi
      
      echo "      \"$table\": " >> "$output_file"
      
      # Export table data as JSON array of objects
      sqlite3 "$db_file" ".timeout $timeout" \
        "SELECT COALESCE(json_group_array(json_object(*)), '[]') FROM (SELECT * FROM \"$table\");" >> "$output_file" 2>/dev/null || echo "[]" >> "$output_file"
      
      first_table=false
    fi
  done < "$tables_file"
  
  rm -f "$tables_file"
  
  # Close JSON structure
  cat >> "$output_file" << EOF

    }
  }
}
EOF
  
  _format_info "JSON export created: $(basename "$output_file")"
}

# Create schema-only backup for database recreation
create_schema_backup() {
  local db_file="${1:?Database file required}"
  local output_file="${2:?Output file required}"
  
  _format_debug "Creating schema-only backup"
  
  cat > "$output_file" << EOF
-- Schema-only backup for database structure recreation
-- Created: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
-- Source: $(basename "$db_file")
-- Generator: VaultWarden-OCI-Minimal Enhanced Backup System
--
-- This file contains only the database structure (tables, indexes, triggers, views)
-- No data is included - use for structure recovery or database migration
--
-- Usage: sqlite3 new_database.db < $(basename "$output_file")
--

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

-- Database schema export
EOF
  
  # Export complete schema
  sqlite3 "$db_file" <<EOF >> "$output_file"
-- Export table schemas, indexes, triggers, and views
.schema

-- Export any additional database pragmas that might be needed
SELECT '-- PRAGMA ' || name || ' = ' || COALESCE('"' || value || '"', 'NULL') || ';'
FROM (
  SELECT 'user_version' as name, CAST(user_version AS TEXT) as value FROM pragma_user_version
  UNION ALL
  SELECT 'application_id' as name, CAST(application_id AS TEXT) as value FROM pragma_application_id
  UNION ALL
  SELECT 'journal_mode' as name, journal_mode as value FROM pragma_journal_mode
) WHERE value != '0' AND value != 'delete';
EOF
  
  cat >> "$output_file" << EOF

COMMIT;
PRAGMA foreign_keys=ON;

-- End of schema backup
-- Database structure recreation complete
EOF
  
  _format_info "Schema backup created: $(basename "$output_file")"
}

# Create comprehensive multi-format backup
create_diverse_backups() {
  local db_file="${1:?Database file required}"
  local output_dir="${2:?Output directory required}"
  local timestamp="${3:?Timestamp required}"
  
  _format_info "Creating diverse backup formats for maximum compatibility and recovery options"
  
  local timeout
  timeout=$(calculate_backup_timeout "$db_file")
  _format_debug "Using calculated timeout: ${timeout}s"
  
  # Prepare database for backup (WAL checkpoint if needed)
  prepare_database_for_backup "$db_file" "$timeout" || _format_warn "Database preparation had issues, continuing with backup"
  
  local backup_files=()
  local failed_formats=()
  
  # 1. Native SQLite binary backup (fastest restore, platform-specific)
  local bin_out="$output_dir/db-native-$timestamp.sqlite3"
  if create_binary_backup "$db_file" "$bin_out" "$timeout"; then
    if verify_backup_integrity "$bin_out" "$db_file"; then
      backup_files+=("$bin_out")
    else
      failed_formats+=("binary")
      rm -f "$bin_out"
    fi
  else
    failed_formats+=("binary")
  fi
  
  # 2. Portable SQL dump with compatibility headers
  local sql_out="$output_dir/db-portable-$timestamp.sql"
  if create_portable_sql_dump "$db_file" "$sql_out" "$timeout"; then
    backup_files+=("$sql_out")
  else
    failed_formats+=("sql")
  fi
  
  # 3. CSV exports for critical tables (human-readable, universal)
  if create_csv_exports "$db_file" "$output_dir" "$timestamp"; then
    # CSV exports create a directory, not a single file
    backup_files+=("$output_dir/csv-exports")
  else
    failed_formats+=("csv")
  fi
  
  # 4. JSON export for structured data (modern, portable)
  local json_out="$output_dir/db-export-$timestamp.json"
  if create_json_export "$db_file" "$json_out" "$timeout"; then
    backup_files+=("$json_out")
  else
    failed_formats+=("json")
  fi
  
  # 5. Schema-only backup for structure recreation
  local schema_out="$output_dir/schema-$timestamp.sql"
  if create_schema_backup "$db_file" "$schema_out"; then
    backup_files+=("$schema_out")
  else
    failed_formats+=("schema")
  fi
  
  # Report results
  local success_count=${#backup_files[@]}
  local total_formats=5
  
  if [ "$success_count" -eq "$total_formats" ]; then
    _format_info "All backup formats created successfully ($success_count/$total_formats)"
  elif [ "$success_count" -gt 0 ]; then
    _format_warn "Partial backup success ($success_count/$total_formats). Failed formats: ${failed_formats[*]}"
  else
    _format_error "All backup formats failed"
    return 1
  fi
  
  # Create backup manifest
  create_backup_manifest "$output_dir" "$timestamp" "$db_file" backup_files[@] failed_formats[@]
  
  return 0
}

# Create backup manifest with metadata
create_backup_manifest() {
  local output_dir="${1:?Output directory required}"
  local timestamp="${2:?Timestamp required}"
  local db_file="${3:?Database file required}"
  local -n successful_files=$4
  local -n failed_formats_ref=$5
  
  local manifest_file="$output_dir/backup-manifest.json"
  
  _format_debug "Creating backup manifest"
  
  cat > "$manifest_file" << EOF
{
  "backup_manifest": {
    "created": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
    "timestamp": "$timestamp",
    "generator": "VaultWarden-OCI-Minimal Enhanced Backup System",
    "manifest_version": "1.0",
    "source_database": {
      "file": "$(basename "$db_file")",
      "size_bytes": $(stat -c%s "$db_file" 2>/dev/null || echo "0"),
      "size_human": "$(du -h "$db_file" 2>/dev/null | cut -f1 || echo "unknown")",
      "sqlite_version": "$(sqlite3 --version 2>/dev/null || echo "unknown")",
      "journal_mode": "$(sqlite3 "$db_file" "PRAGMA journal_mode;" 2>/dev/null || echo "unknown")"
    },
    "backup_formats": {
      "successful": [
$(printf '        "%s"' "${successful_files[@]}" | sed 's|.*/||g' | paste -sd ',' | sed 's/,/",\n        "/g' | sed 's/$/"/g' 2>/dev/null || echo "")
      ],
      "failed": [
$(printf '        "%s"' "${failed_formats_ref[@]}" | paste -sd ',' | sed 's/,/",\n        "/g' | sed 's/$/"/g' 2>/dev/null || echo "")
      ]
    },
    "recovery_instructions": {
      "binary_restore": "sqlite3 new_db.sqlite3 '.restore db-native-*.sqlite3'",
      "sql_restore": "sqlite3 new_db.sqlite3 < db-portable-*.sql",
      "json_usage": "Parse JSON for programmatic data access",
      "csv_usage": "Import individual tables as needed",
      "schema_usage": "sqlite3 new_db.sqlite3 < schema-*.sql (structure only)"
    }
  }
}
EOF
  
  _format_info "Backup manifest created: $(basename "$manifest_file")"
}

# Validate backup compatibility across formats
validate_backup_compatibility() {
  local backup_dir="${1:?Backup directory required}"
  
  _format_info "Validating backup cross-platform compatibility"
  
  local validation_passed=true
  
  # Test SQL dump compatibility by attempting restore to temporary database
  local sql_dump
  sql_dump=$(find "$backup_dir" -name "db-portable-*.sql" | head -n1)
  if [ -n "$sql_dump" ] && [ -f "$sql_dump" ]; then
    local temp_db
    temp_db=$(mktemp -p "${TMPDIR:-/tmp}" test-restore.XXXXXX.sqlite3)
    
    _format_debug "Testing SQL dump restore compatibility"
    if sqlite3 "$temp_db" < "$sql_dump" 2>/dev/null; then
      if sqlite3 "$temp_db" "PRAGMA integrity_check;" 2>/dev/null | grep -q '^ok$'; then
        _format_info "✓ SQL dump format validation passed"
      else
        _format_warn "✗ SQL dump integrity check failed after restore"
        validation_passed=false
      fi
    else
      _format_warn "✗ SQL dump format validation failed - restore unsuccessful"
      validation_passed=false
    fi
    rm -f "$temp_db"
  fi
  
  # Validate binary backup integrity
  local bin_backup
  bin_backup=$(find "$backup_dir" -name "db-native-*.sqlite3" | head -n1)
  if [ -n "$bin_backup" ] && [ -f "$bin_backup" ]; then
    _format_debug "Testing binary backup integrity"
    if sqlite3 "$bin_backup" "PRAGMA integrity_check;" 2>/dev/null | grep -q '^ok$'; then
      _format_info "✓ Binary backup integrity validation passed"
    else
      _format_warn "✗ Binary backup integrity validation failed"
      validation_passed=false
    fi
  fi
  
  # Validate JSON format
  local json_export
  json_export=$(find "$backup_dir" -name "db-export-*.json" | head -n1)
  if [ -n "$json_export" ] && [ -f "$json_export" ]; then
    _format_debug "Testing JSON format validity"
    if command -v jq >/dev/null 2>&1; then
      if jq empty < "$json_export" >/dev/null 2>&1; then
        _format_info "✓ JSON export format validation passed"
      else
        _format_warn "✗ JSON export format validation failed"
        validation_passed=false
      fi
    else
      _format_debug "jq not available, skipping JSON validation"
    fi
  fi
  
  # Check CSV exports
  local csv_dir="$backup_dir/csv-exports"
  if [ -d "$csv_dir" ]; then
    local csv_count
    csv_count=$(find "$csv_dir" -name "*.csv" | wc -l)
    if [ "$csv_count" -gt 0 ]; then
      _format_info "✓ CSV exports validation passed ($csv_count files)"
    else
      _format_warn "✗ No CSV export files found"
      validation_passed=false
    fi
  fi
  
  if [ "$validation_passed" = true ]; then
    _format_info "All backup format validations passed"
    return 0
  else
    _format_warn "Some backup format validations failed"
    return 1
  fi
}
