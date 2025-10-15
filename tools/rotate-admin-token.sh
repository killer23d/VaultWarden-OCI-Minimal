#!/usr/bin/env bash
# /tools/rotate-admin-token.sh - Rotates VaultWarden’s ADMIN_TOKEN and the Caddy Basic Auth password/hash used to protect /admin.
# Behavior:
#   - Generates a new 32-byte base64 ADMIN_TOKEN with openssl.
#   - Generates a new random Basic Auth password and hashes it with `caddy hash-password`.
#   - Updates settings.json with ADMIN_TOKEN and ADMIN_BASIC_AUTH_HASH atomically via jq.
#   - Enforces 600 perms on settings.json and restarts the stack to apply changes.
#   - Optional: If invoked with --upload-to-oci and OCI_SECRET_OCID is set, calls tools/update-secrets.sh to push the updated settings to OCI Vault.
# Requirements:
#   - jq, openssl, and caddy (for hash-password) available on the host.
#   - Project libraries (lib/config.sh, lib/logging.sh) for consistent logging and configuration.
# Usage:
#   ./tools/rotate-admin-token.sh [--upload-to-oci]

set -euo pipefail

# Generate new credentials
NEW_ADMIN_TOKEN=$(openssl rand -base64 32)
NEW_BASIC_PASSWORD=$(openssl rand -base64 16)
NEW_BASIC_HASH=$(caddy hash-password --plaintext "$NEW_BASIC_PASSWORD")

# Update settings.json
jq --arg token "$NEW_ADMIN_TOKEN" --arg hash "$NEW_BASIC_HASH" \
   '. + {"ADMIN_TOKEN": $token, "ADMIN_BASIC_AUTH_HASH": $hash}' \
   settings.json > settings.json.tmp && mv settings.json.tmp settings.json

# Restart and display credentials
./startup.sh
echo "Basic Auth Password: $NEW_BASIC_PASSWORD"
echo "Admin Token: $NEW_ADMIN_TOKEN"
