# Troubleshooting

## Common issues

- Startup fails: run ./tools/init-setup.sh to confirm prerequisites, then ./tools/monitor.sh once to attempt self-heal and capture logs. [attached_file:2]
- Secret errors: verify OCI_SECRET_OCID is set or settings.json is valid JSON with all required keys using jq. [attached_file:2]
- Restore health failures: re-run ./tools/restore.sh --interactive and select database-only to isolate DB integrity issues. [attached_file:2]

## Getting logs

- Use docker compose logs --tail 200 and the logs/monitor.log output to triage recurring failures after scheduled self-heal attempts. [attached_file:2]
