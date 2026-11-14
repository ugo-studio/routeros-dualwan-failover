# Security

## What is sensitive

| Item | Where it lives | Commit it? |
| --- | --- | --- |
| WireGuard private keys, preshared keys | Router only (`wg-commercial`, the `WG-Profiles` script) | **Never** |
| Router exports (`/export`) and backups (`.backup`) | Your computer | **Never** (they can include keys and passwords) |
| VPN provider `.conf` files | Your computer | **Never** |
| Scripts in `src/` and files in `dist/` | This repo | Yes, they contain placeholders only |

All example keys and addresses in this repo are placeholders. IPs use the documentation ranges (`203.0.113.0/24`, RFC 5737) or well-known public resolvers.

## Safeguards in this repo

- `.gitignore` blocks `*.backup`, `*.conf`, exports, and anything under `local/` or `private/`.
- `tools/check_secrets.py` fails if a file contains a WireGuard-key-shaped string, a private key block, or an email address. CI runs it on every push and pull request.

If you fork this repo, keep your own settings in `local/` (ignored by git).

## On the router

- The `WG-Profiles` script holds keys in plain text. Any account that can read scripts can see them, so use separate, limited router accounts for anyone else.
- Keep WebFig, the REST API and SSH off the WAN side. The default RouterOS firewall already drops them from the WAN interface list, and `FO-Ports` adds both WAN ports to that list.
- `WG-Profiles-backup` (created by `WG-Import`) also contains keys. Delete it when you no longer need it.

## Reporting

Found a problem that could expose someone's keys or network? Open a private security advisory on this repository (**Security → Report a vulnerability**) instead of a public issue.
