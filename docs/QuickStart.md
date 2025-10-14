# Quick Start

## Prerequisites

- Docker engine and compose plugin, jq, gpg, sqlite3; optional OCI CLI for Vault workflows. [attached_file:2]

## Setup

- Clone repository and set execute permissions on scripts. [attached_file:2]
- Run ./tools/init-setup.sh to perform preflight checks, create directories, and optionally launch the settings wizard. [attached_file:2]
- Prefer OCI Vault by exporting OCI_SECRET_OCID (or legacy OCISECRET_OCID) so secrets are loaded securely in-memory at runtime. [attached_file:2]
- If not using OCI Vault, copy settings.json.example to settings.json and fill required keys; nothing is written beyond this unless chosen. [attached_file:2]

## Launch

- Execute ./startup.sh to source lib/config.sh and start docker-compose with health-based dependencies. [attached_file:2]
- Visit the web endpoint and admin panel using the configured APP_DOMAIN with TLS handled by Caddy. [attached_file:2]
