# Backup and Restore

## Database backups

- Run ./tools/db-backup.sh to produce compressed, encrypted SQLite artifacts (binary and SQL) with integrity checks. [attached_file:2]
- Optional rclone upload uses RCLONE_REMOTE and RCLONE_PATH, and local retention is controlled by BACKUP_KEEP_LOCAL. [attached_file:2]

## Full system backups

- Run ./tools/create-full-backup.sh to package volumes, project config, and the latest DB backup into one encrypted archive. [attached_file:2]
- Use FULL_BACKUP_KEEP_LOCAL to keep a fixed number of historical archives on the host. [attached_file:2]

## Restore

- Run ./tools/restore.sh --interactive to stop services safely, decrypt artifacts, restore DB or volumes, restart, and verify health. [attached_file:2]
- For new hosts, run ./tools/rebuild-vm.sh then ./tools/restore.sh --interactive to complete recovery using encrypted backups. [attached_file:2]
