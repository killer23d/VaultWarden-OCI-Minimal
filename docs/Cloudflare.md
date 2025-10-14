# Cloudflare

## IP awareness

- The `tools/update-cloudflare-ips.sh` script automatically fetches the latest Cloudflare CIDR ranges from their official API endpoints to keep logs and bans accurate.

## Caddy integration

- The generated `caddy/cloudflare-ips.caddy` file is imported by the main `Caddyfile` to apply real client IP logic, ensuring VaultWarden and Fail2ban see the actual visitor's IP address instead of Cloudflare's.

## DNS and proxy

- Configure a proxied (orange-clouded) DNS A or CNAME record for your application domain in the Cloudflare dashboard.
- For optimal security, set the SSL/TLS encryption mode to **Full (Strict)**. This ensures traffic is encrypted from the client to Cloudflare, and from Cloudflare to your Caddy server.