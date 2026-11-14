# routeros-dualwan-failover

Sub-second dual-WAN failover for MikroTik RouterOS 7, built for a **Starlink (primary) + 4G/LTE router (backup)** setup, with an optional WireGuard **VPN shield** that keeps your public IP stable across switches.

Everything is configured from one settings script on the router and installed with two `/import` commands.

## Features

- **Fast cut-over:** a 5-ping burst every second through the primary link only. Netwatch disables the primary route the moment a burst fails, usually in under a second.
- **Configurable switch-back:** the primary must stay healthy for `FOHoldSec` seconds (default 2) before traffic returns.
- **No "ping escape":** the monitor host is pinned to the primary gateway, with a blackhole fallback, so the probe can never succeed over the backup.
- **Backup-aware:** never fails over to a backup port with no link, and restores the primary immediately if the backup link drops.
- **VPN shield:** `auto` (on after repeated drops), `always` or `off`. The pause state survives reboots, and FastTrack is handled.
- **Multiple WireGuard profiles:** switch servers with one line. You can import the config already on the router as a profile.
- **Port mapping:** any two ports as WAN1/WAN2; retired WAN ports go back to the LAN bridge.
- **Captive portal friendly:** detects a Hotspot server and keeps the login page outside the tunnel.
- **Clean footprint:** every object is named or commented `FO-…`.

## Requirements

- RouterOS **7.24 or newer** (written for a hAP ac²; any RouterOS 7 router with two free Ethernet ports should work)
- Primary WAN that hands out an address by DHCP (Starlink in bypass/router mode)
- Backup router that hands out an address by DHCP (MTN, Airtel, Glo or any LTE router)
- Optional: a WireGuard VPN provider (Mullvad, Proton and so on) for the shield

## Quick start

> Back up first: `/system backup save name=pre-fo-v2` and `/export file=pre-fo-v2`. Do the install over WiFi.

1. Download the files in [`dist/`](dist/) and upload them in WebFig → **Files**.
2. In **Terminal**:

   ```routeros
   # Only if you used the v1 manual:
   /import file-name=fo-cleanup-v1.rsc
   # Install / upgrade (safe to re-run; keeps your settings and profiles):
   /import file-name=fo-install-v2.rsc
   ```

3. Check it:

   ```routeros
   /system script run FO-Status
   ```

4. Adjust **System → Scripts → Starlink-Settings** if needed, then run **FO-Apply**.

The full guide is in **[docs/MANUAL.md](docs/MANUAL.md)**. A styled copy is [docs/manual.html](docs/manual.html), which you can download and open in a browser.

## Common tasks

| Task | Command |
| --- | --- |
| Status | `/system script run FO-Status` |
| Apply changed settings | `/system script run FO-Apply` |
| Change WAN ports | Edit `FOStarlinkPort` / `FOMTNPort`, then `/system script run FO-Ports` |
| Save the live VPN as a profile | `:global WGImportName "name"; /system script run WG-Import` |
| Switch VPN server | `:global WGPick "name"; /system script run WG-Apply` |
| Pause / resume VPN | `/system script run FO-VPN-Toggle` |

## Repository layout

```text
dist/                   Ready-to-import files (generated, do not edit by hand)
  fo-install-v2.rsc       Installer / upgrader
  fo-cleanup-v1.rsc       Removes the v1 setup
  fo-wg-import.rsc        Saves the router's live WireGuard config as a profile
docs/
  MANUAL.md               Full manual (generated from tools/manual.template.md)
  manual.html             Same manual as a standalone page
src/
  scripts/*.rsc           Readable source of every script the installer creates
  fo-cleanup-v1.rsc       Cleanup source
tools/
  build.py                Builds dist/ and docs/MANUAL.md
  build_html.py           Builds docs/manual.html
  check_secrets.py        Fails if anything key-like or personal is committed
  manual.template.md      Manual text
```

## Building

```sh
pip install markdown
python3 tools/build.py && python3 tools/build_html.py
python3 tools/check_secrets.py
```

Edit the sources in `src/` and `tools/manual.template.md`, never the generated files. CI rebuilds on every push and fails if `dist/` or `docs/` are out of date, or if the secret check finds anything.

## Security

- **No secrets are stored in this repo.** WireGuard keys are only ever read from or written to your router.
- WG-Profiles keeps keys in a script on the router. Limit router logins to people you trust.
- **Never commit** router exports, backups or a filled-in WG-Profiles. `.gitignore` blocks the usual file names.
- See [SECURITY.md](SECURITY.md).

## Disclaimer

These scripts change routing, firewall and DHCP configuration. They are provided as-is. Test them on your own router with a backup in hand.

## License

[MIT](LICENSE)
