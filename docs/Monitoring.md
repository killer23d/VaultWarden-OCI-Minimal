# Monitoring

## Overview

- Lightweight host-based checks verify container health and attempt staged recovery with up to three rounds before alerting. [attached_file:2]

## Cron

- Example: */30 * * * * cd /path/to/VaultWarden-OCI-Slim && ./tools/monitor.sh >> logs/cron.log 2>&1 to run every 30 minutes. [attached_file:2]
- Configure ALERT_EMAIL_TO or rely on ADMIN_EMAIL for notification targets, with a file-based fallback if no MTA exists. [attached_file:2]
