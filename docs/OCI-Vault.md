# OCI Vault

## Concepts

- Secrets are stored as a single JSON object and retrieved into memory during startup without writing to disk. [attached_file:2]

## Bootstrap

- Ensure OCI CLI is configured and export OCI_COMPARTMENT_OCID, OCI_VAULT_OCID, and OCI_KEY_OCID in the shell. [attached_file:2]
- Run tools/oci-setup.sh bootstrap settings.json to create a new secret and capture the returned OCID. [attached_file:2]
- Export OCI_SECRET_OCID to make startup.sh prefer the managed secret over a local file. [attached_file:2]

## Update and view

- tools/oci-setup.sh get prints the decoded JSON for validation, and update replaces secret content atomically. [attached_file:2]
