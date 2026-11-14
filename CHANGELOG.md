# Changelog

## 2.0.0 (2026-11-14)

- Sub-second failover: Netwatch ICMP burst probe disables the primary route directly
- Configurable switch-back hold (`FOHoldSec`)
- All settings in one script (`Starlink-Settings`), applied by `FO-Apply`
- Multiple WireGuard profiles (`WG-Profiles`), switch with `WG-Apply`
- `WG-Import` saves the router's live WireGuard config as a profile
- Configurable WAN ports (`FO-Ports`); retired WAN ports return to the LAN bridge
- Primary restored immediately if the backup link drops
- VPN pause survives reboots
- Hotspot detected automatically for the VPN shield rule
- MSS clamp limited to tunnel traffic
- `FO-Status` summary script
- `fo-cleanup-v1.rsc` removes the v1 setup

## 1.0.0

- Manual setup: 2-second ping monitor, polling "Brain" scheduler, VPN shield after repeated drops
