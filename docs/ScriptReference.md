# Script Reference Guide

## Overview

This guide provides a concise, task-oriented reference for all scripts included in VaultWarden-OCI-Minimal. It explains each script’s purpose, key options, inputs/outputs, and example usage. Use this when you need to quickly find the right script and the correct invocation.

## Usage Conventions

- Run all scripts from the project root directory unless otherwise specified.
- Prefix with `sudo` where system changes are required (install, permissions, cron, network, system directories).
- Enable debug output with `DEBUG=1` for more verbose logs.
- Most scripts rely on the dynamic configuration libraries under `./lib/` – do not hardcode paths.

```bash
# Examples
DEBUG=1 ./startup.sh
sudo DEBUG=1 ./tools/init-setup.sh --auto
```

---

## Top-Level Entrypoints

### startup.sh
- Purpose: Single, authoritative entrypoint to start, validate, and display status for the stack.
- Responsibilities:
  - Load configuration (OCI Vault or local settings.json)
  - Prepare runtime environment, required directories, and placeholders
  - Run pre-flight checks and start services via Docker Compose
  - Validate container health and display service info
- Common options:
  - `--validate`: Validate configuration and prerequisites only (no start)
  - `-h, --help`: Help text
- Examples:
```bash
./startup.sh
./startup.sh --validate
DEBUG=1 ./startup.sh
```

---

## Setup and Configuration

### tools/init-setup.sh
- Purpose: One-time system initialization and hardening.
- Actions:
  - Install Docker, Compose plugin, jq, curl, openssl (and optional: fail2ban, ufw, gettext)
  - Configure firewall (UFW) and enable fail2ban if present
  - Generate `settings.json` with secure tokens
  - Create directory structure in `/var/lib/{project-name}` and project symlinks
  - Install cron jobs for backups, monitoring, Cloudflare IP updates
- Options:
  - `--auto`: Non-interactive install with safe defaults
  - `-h, --help`: Help text
- Examples:
```bash
sudo ./tools/init-setup.sh
sudo ./tools/init-setup.sh --auto
```

### tools/oci-setup.sh
- Purpose: Configure OCI Vault integration on the host.
- Actions:
  - Validate OCI CLI configuration and connectivity
  - Prompt for or detect `OCI_SECRET_OCID`
  - Write `/etc/systemd/system/{project}.env` with `OCI_SECRET_OCID` (600 perms)
  - Test configuration loading from Vault
- Examples:
```bash
./tools/oci-setup.sh
```

### tools/update-secrets.sh
- Purpose: Sync secrets between local `settings.json` and OCI Vault.
- Typical tasks:
  - Upload local config to Vault as a new secret version
  - Download current secret from Vault to local file (with backup/validation)
- Common options:
  - `--upload-to-oci`: Push local `settings.json` to OCI Vault
  - `--download-from-oci`: Pull secret from OCI Vault to local `settings.json`
  - `--dry-run`: Show planned actions without changes
- Examples:
```bash
./tools/update-secrets.sh --upload-to-oci
./tools/update-secrets.sh --download-from-oci --dry-run
```

---

## Operation and Health

### tools/monitor.sh
- Purpose: Health checks, self-healing, reporting, and alerts.
- Capabilities:
  - Validate container health, services, SSL, backups, and resources
  - Attempt recovery (restart failed services, clean temp/logs)
  - Generate status reports and send alert emails
- Useful options:
  - `--summary`: Quick status overview
  - `--verbose`: Detailed checks and outputs
  - `--comprehensive`: Run all check suites
  - `--restart-failed`: Restart unhealthy services
  - `--backup-status`: Show backup status
  - `--resources`: Disk/memory/CPU summary
  - `--report`: Emit machine-readable report
- Examples:
```bash
./tools/monitor.sh --summary
./tools/monitor.sh --comprehensive
./tools/monitor.sh --restart-failed
```

### tools/update-cloudflare-ips.sh
- Purpose: Fetch Cloudflare IPv4/v6 CIDR ranges and update Caddy allowlists.
- Behavior:
  - Robust retries, basic response validation, and backups of previous lists
  - Writes to `caddy/cloudflare-ips.caddy` and `/etc/caddy-extra/cloudflare-ips.caddy`
- Options:
  - `-q, --quiet`: Minimal output
  - `-f, --force`: Force write even if no changes
  - `-n, --dry-run`: No write, show proposed changes
- Examples:
```bash
./tools/update-cloudflare-ips.sh
./tools/update-cloudflare-ips.sh --force
./tools/update-cloudflare-ips.sh --dry-run
```

### tools/render-ddclient-conf.sh
- Purpose: Render `ddclient.conf` from template and environment/config.
- Inputs:
  - Template: defaults to `templates/ddclient.conf.tmpl` if not provided
  - Outputs to `/etc/ddclient.conf` by default (or custom via 2nd arg)
  - Requires `DDCLIENT_PROTOCOL, DDCLIENT_LOGIN, DDCLIENT_PASSWORD, DDCLIENT_ZONE, DDCLIENT_HOST`
- Examples:
```bash
DDCLIENT_PROTOCOL=cloudflare DDCLIENT_LOGIN=you DDCLIENT_PASSWORD=token DDCLIENT_ZONE=example.com DDCLIENT_HOST=vault.example.com ./tools/render-ddclient-conf.sh

# Custom template and output file
./tools/render-ddclient-conf.sh ./templates/ddclient.conf.tmpl ./ddclient/ddclient.conf
```

---

## Backup and Restore

### tools/db-backup.sh
- Purpose: Create encrypted, compressed database backups in multiple formats.
- Formats: `binary, sql, json, csv` (one or all)
- Key options:
  - `--format <type>`: Select format (default: all)
  - `--validate`: Verify backup after creation
  - `--verify <file>`: Verify an existing backup archive
  - `--passphrase <string>`: Override encryption passphrase
  - `--dry-run`: Simulate without writing files
  - `--quiet`: Reduce output
- Examples:
```bash
./tools/db-backup.sh --format sql --validate
./tools/db-backup.sh --dry-run
./tools/db-backup.sh --verify /var/lib/*/backups/database/backup_*.sql.gz.gpg
```

### tools/create-full-backup.sh
- Purpose: Full system backup (database, configs, SSL, recent logs).
- Options:
  - `--include-logs`: Include recent logs
  - `--include-images`: Include Docker images (large!)
  - `--name <label>`: Custom backup name prefix
  - `--report-only`: Output planned contents without creating archive
- Examples:
```bash
./tools/create-full-backup.sh --include-logs
./tools/create-full-backup.sh --name pre-migration
```

### tools/restore.sh
- Purpose: Interactive and scripted restore (database-only or full system).
- Modes:
  - Interactive: `./tools/restore.sh` then follow prompts
  - Non-interactive: pass backup path and flags
- Options:
  - `--database-only <file>`: Restore DB from specific archive
  - `--config-only <file>`: Restore config only
  - `--latest`: Use most recent backup
  - `--test` / `--dry-run`: Validate/archive check without restore
- Examples:
```bash
./tools/restore.sh
./tools/restore.sh --database-only /path/to/db_backup.sql.gz.gpg
./tools/restore.sh /path/to/full_backup_YYYYMMDD_HHMMSS.tar.gz.gpg
```

---

## Database Maintenance

### tools/sqlite-maintenance.sh
- Purpose: Maintain SQLite health and performance.
- Capabilities:
  - VACUUM, integrity checks, REINDEX, ANALYZE, stats, and lock detection
- Common options:
  - `--full`: Full maintenance (VACUUM + checks + analyze)
  - `--quick`: Fast maintenance
  - `--check`: Quick integrity check
  - `--verify`: Deep integrity verification
  - `--reindex`: Rebuild all indexes
  - `--analyze` / `--stats`: Analyze query planner and show stats
- Examples:
```bash
./tools/sqlite-maintenance.sh --full
./tools/sqlite-maintenance.sh --check
./tools/sqlite-maintenance.sh --analyze --stats
```

---

## Libraries (for reference)

### lib/config.sh
- Responsibilities: Dynamic project identity, paths, configuration loading, OCI Vault integration, validation, and environment export.
- Notable exports: `PROJECT_NAME, PROJECT_STATE_DIR, CONFIG_VALUES[*], CONFIG_SOURCE`.
- Caller helpers: `load_config, get_config_value, set_config_value, validate_configuration, backup_current_config, get_project_paths`.

### lib/system.sh
- Responsibilities: Package installation, system service management, secure file/directory operations, and utility helpers (backup file, test connectivity, compose helpers).

### lib/validation.sh
- Responsibilities: OS/resource checks, docker/compose checks, network checks, compose file validation, service health validation.

### lib/logging.sh
- Responsibilities: Consistent, color-coded logging, sections, headers, numbered items, and debug toggles.

### lib/monitoring.sh
- Responsibilities: Modular health checks, recovery actions, and report helpers used by tools/monitor.sh.

---

## Task to Script Mapping

- Install and initialize the system → `tools/init-setup.sh`
- Start or validate services → `startup.sh`
- Check health or recover from issues → `tools/monitor.sh`
- Backup database or full system → `tools/db-backup.sh`, `tools/create-full-backup.sh`
- Restore data or system → `tools/restore.sh`
- Maintain SQLite database → `tools/sqlite-maintenance.sh`
- Sync secrets with OCI Vault → `tools/update-secrets.sh`, `tools/oci-setup.sh`
- Update Cloudflare IP allowlist → `tools/update-cloudflare-ips.sh`
- Render Dynamic DNS config → `tools/render-ddclient-conf.sh`

---

## Best Practices

- Always use `startup.sh` to launch the stack; avoid `docker compose up` directly.
- Keep `settings.json` under 600 permissions; never commit secrets.
- Test backups monthly: create, verify, and test-restore.
- Use `--validate` paths before applying changes in production windows.
- Favor non-interactive flags in CI/automation with `--auto`, `--dry-run`, and `--report-only`.

This script reference is intended to be a quick, authoritative index for all operational tasks in VaultWarden-OCI-Minimal, aligned with the dynamic, portable design and small-team production needs.
