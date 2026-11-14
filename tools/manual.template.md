# MIKROTIK DUAL-WAN FAILOVER, VPN SHIELD & VOUCHER SYSTEM MANUAL (v2)

**Architecture:** Sub-second Starlink → MTN failover + configurable switch-back + VPN Shield with switchable WireGuard profiles + Captive Portal
**Written for:** RouterOS 7.24.x on a hAP ac² (works on any RouterOS 7.24+ router)
**Files:** `fo-cleanup-v1.rsc` (removes the v1 setup) · `fo-install-v2.rsc` (installs v2) · `fo-wg-import.rsc` (saves your live VPN as a profile)

---

## What changed from v1

| | v1 | v2 |
| --- | --- | --- |
| Detection | 1 ping every 2s, Brain polls every 2s (≈2–4s to switch) | 5-ping burst every second; Netwatch pulls the route itself (typically under 1s) |
| Switch back | Fixed 4s | `FOHoldSec` seconds (default 2) |
| Settings | Hard-coded in many commands | One script: **Starlink-Settings** |
| WireGuard | One server, edit by hand | Any number of profiles in **WG-Profiles**, switch with one line |
| Ports | ether1 / ether2 fixed | Any two ports, set in settings, applied by **FO-Ports** |
| MTN cable unplugged while on backup | Traffic stayed off Starlink | Starlink route restored right away |
| VPN pause | Lost on reboot | Survives reboot (pause = tunnel interface disabled) |
| Shield with no Hotspot | `hotspot=auth` blocked it | Hotspot is detected automatically |
| MSS clamp | All traffic | Tunnel traffic only (direct traffic keeps full speed) |
| Install | Many paste blocks | Two files, two commands |

Every object v2 creates is named or commented `FO-…`, so it is easy to find and remove.

---

## 1. Network Topology

```text
                          +------------------------+
                          |  Starlink Mini (WAN1)  |  Primary
                          |  FOStarlinkPort        |  (default ether1)
                          +-----------+------------+
                                      |
+---------------------+   +-----------v------------+   +-----------------------+
|  Local LAN / WiFi   <---+    MikroTik hAP ac²    +--->  MTN 4G Router (WAN2) |  Backup
|  (192.168.88.0/24)  |   |    (Routing Engine)    |   |  FOMTNPort            |
+---------------------+   +-----------+------------+   |  (default ether2)     |
                                      | WireGuard       +-----------------------+
                          +-----------v------------+
                          |  Commercial VPN        |  Static public IP
                          |  (active WG profile)   |  ("session shield")
                          +------------------------+
```

---

## 2. How the failover works

```text
 Netwatch "FO-Probe" ── bursts of 5 pings, 100ms apart, every 1s, to 9.9.9.9
       │                (9.9.9.9 can ONLY go through Starlink; a blackhole
       │                 route drops it otherwise, so it can't "escape" via MTN)
       │
       ├─ burst fails (≥50% loss or avg > 300ms) ──► disables FO-Starlink-Main
       │                                             instantly (if MTN link is up)
       │                                             → traffic flows over MTN
       ▼
 FO-Brain (every 1s)
   • counts drops; after FOFlapLimit drops in FOFlapWindow → VPN shield ON (auto mode)
   • Starlink healthy for FOHoldSec checks in a row → FO-Starlink-Main back ON
   • MTN cable/link gone while on backup → Starlink route back ON immediately
 FO-Cooldown (every FOFlapWindow)
   • quiet window → shield OFF (auto mode), drop counter reset
```

**Why the VPN shield matters more now:** each switch changes your public IP, which drops calls and downloads. With a sub-second trigger, switches happen more often, and Starlink has frequent short dropouts. With the shield on, your apps only ever see the VPN's IP, so a switch is just a short pause. If you mostly care about calls, set `FOShieldMode` to `"always"`.

---

## 3. Install / Upgrade

> ⚠️ Do this on **WiFi** (or a LAN port that is not one of the two WAN ports). Internet will drop for a few seconds while the WAN ports are rebuilt.

### Step 1: Back up the current config

In **Terminal**:

```routeros
/system backup save name=pre-fo-v2
/export file=pre-fo-v2
```

### Step 2: Upload the two files

WebFig (`192.168.88.1`) → **Files** → **Upload**, and choose `fo-cleanup-v1.rsc` and `fo-install-v2.rsc`.

### Step 3: Remove v1, install v2

In **Terminal**:

```routeros
/import file-name=fo-cleanup-v1.rsc
/import file-name=fo-install-v2.rsc
```

- If you never used the v1 manual, skip the cleanup line.
- If something fails, run it again with `verbose=yes` at the end to see which line stopped it.

What the installer does:

1. Locks the bridge MAC (one time).
2. Installs the program scripts (`FO-Apply`, `FO-Ports`, `FO-Brain`, `FO-Cooldown`, `FO-Boot`, `FO-Status`, `FO-VPN-Toggle`, `WG-Apply`, `WG-Import`).
3. Creates **Starlink-Settings** with the defaults (ether1 = Starlink, ether2 = MTN). An older non-v2 `Starlink-Settings` is renamed to `Starlink-Settings-old` rather than deleted, so copy any custom values across.
4. Creates **WG-Profiles** and imports your current VPN as a profile named `current`.
5. Runs `FO-Apply` and `FO-Boot`.

Re-importing the installer later (for an update) replaces the program scripts but **keeps** your Starlink-Settings and WG-Profiles.

### Step 4: Check it

```routeros
/system script run FO-Status
```

You should see `Internet via: Starlink` and `Starlink probe: up` (the probe waits about 30s after a reboot before it starts).

### Step 5: Check your imported VPN profile

**System → Scripts → WG-Profiles** should contain a `current` line with one IPv4 `/32` address.

- **No `current` line, or the wrong address:** run the WireGuard import (section 6.1). It reads what's live on the router and picks the newest tunnel address, which is the right one in most v1 setups.
- **Address correct:** run `WG-Apply` once to remove any stale extra addresses from the tunnel:

```routeros
/system script run WG-Apply
```

**Fresh router (no existing VPN):** add a profile as in section 6, then run `WG-Apply`. Until then the shield has no tunnel to use, so leave `FOShieldMode` on `"auto"` or `"off"`.

---

## 4. Settings (Starlink-Settings)

**To change a setting:** **System → Scripts** → open **Starlink-Settings** → edit the value → **OK** → run **FO-Apply**.

| Setting | Default | What it does |
| --- | --- | --- |
| `FOStarlinkPort` | `"ether1"` | Port the Starlink Mini is on |
| `FOMTNPort` | `"ether2"` | Port the MTN router is on |
| `FOLANBridge` | `"bridge"` | LAN bridge; a port that stops being WAN is returned here |
| `FOLANSubnet` | `"192.168.88.0/24"` | LAN subnet, never sent into the VPN |
| `FOMonitorHost` | `"9.9.9.9"` | Host pinged only through Starlink. **Never use it as DNS** |
| `FOProbeInterval` | `"1s"` | How often a burst starts |
| `FOProbeCount` | `5` | Pings per burst |
| `FOProbeSpacing` | `"100ms"` | Gap between pings |
| `FOProbeTimeout` | `"500ms"` | Wait per reply |
| `FOProbeLoss` | `50` | Loss % that fails a burst (lower = more sensitive) |
| `FOProbeMaxAvg` | `"300ms"` | Average ping that fails a burst (the RouterOS default of 100ms is too strict for Starlink) |
| `FOHoldSec` | `2` | Seconds Starlink must stay healthy before switching back |
| `FOMTNDistance` | `2` | MTN backup route distance (must be above 1) |
| `FOShieldMode` | `"auto"` | `"auto"`, `"always"` or `"off"` (see section 2) |
| `FOFlapLimit` | `2` | Drops in one window that turn the auto shield on |
| `FOFlapWindow` | `"10m"` | Length of the drop-counting window |
| `FOWGIf` | `"wg-commercial"` | WireGuard interface used by the shield |
| `FOMSS` | `1240` | TCP MSS inside the tunnel (MTU − 40) |
| `FOHotspot` | `"auto"` | `"auto"` detects a Hotspot server; or `"yes"` / `"no"` |
| `FODNS` | `"8.8.8.8,1.1.1.1"` | Router DNS servers |

**Tuning tips**

- **Switches too often on tiny blips:** raise `FOProbeLoss` to `70`, or `FOProbeMaxAvg` to `"500ms"`.
- **Bounces back to Starlink too soon:** raise `FOHoldSec` (5–10 is a good range for a dish with obstructions).
- **Shield turns on too eagerly:** raise `FOFlapLimit`, or shorten `FOFlapWindow`.

> There's deliberately no terminal shortcut for settings. `FO-Apply` always reloads Starlink-Settings, so the script stays the single source of truth.

---

## 5. Changing which port is Starlink / MTN

1. Plug the cables into the new ports.
2. In **Starlink-Settings**, set `FOStarlinkPort` and `FOMTNPort`, for example `"ether3"` and `"ether4"`.
3. Run `FO-Apply` (or just `FO-Ports` if nothing else changed).

`FO-Ports` then:

- takes the new ports out of the LAN bridge and adds them to the `WAN` list;
- moves the DHCP clients (`FO-Starlink`, `FO-MTN`) to the new ports;
- returns any old WAN port to the LAN bridge (marked `FO-released`).

Swapping the two (Starlink on ether2, MTN on ether1) works the same way.

---

## 6. WireGuard profiles (WG-Profiles)

### 6.1 Move your current VPN into a profile (WG-Import)

This saves the WireGuard config that is live on the router (`wg-commercial`) as a profile, with no copying of keys by hand. Use it to bring your v1 VPN into v2, or any time you've changed the tunnel by hand and want to keep that config.

**Option A: with the file** (works before or after installing v2)

1. Upload `fo-wg-import.rsc` in **Files**.
2. In **Terminal**:

```routeros
/import file-name=fo-wg-import.rsc
```

This installs the `WG-Import` script and runs it once, saving the profile as `current`.

**Option B: v2 already installed** (`WG-Import` is already on the router)

```routeros
# Save as "current"
/system script run WG-Import
# Or save under a name of your choice
:global WGImportName "mullvad-lon"; /system script run WG-Import
```

What it does:

- **Reads** the private key, MTU, peer public key, preshared key, endpoint and port from the tunnel.
- **Picks the address:** if the tunnel has several (stale addresses left over from v1), it takes the newest one and lists all of them in the **Log** so you can check.
- **Merges, doesn't replace:** other profiles stay, and an existing profile with the same name is updated.
- **Backs up first:** your previous WG-Profiles is saved as `WG-Profiles-backup` (WG-Import rewrites WG-Profiles one line per profile, so hand-written notes in it are not kept). Delete the backup when you're happy.
- **Makes the imported profile the active one** (`WGActive`), since it's what the tunnel is already running.

Afterwards, run `WG-Apply` once to clear any stale addresses, then `FO-Status` to confirm a recent handshake.

### 6.2 Add a server

Open **System → Scripts → WG-Profiles**. Copy the example line, remove the leading `#`, give it a name and fill it from your provider's `.conf` file:

```routeros
:set ($WGProfiles->"proton-nl") {"priv"="<PrivateKey>";"pub"="<PublicKey>";"psk"="";"addr"="10.2.0.2/32";"host"="203.0.113.30";"port"=51820;"mtu"=1280}
```

| Key | From the .conf | Notes |
| --- | --- | --- |
| `priv` | `[Interface] PrivateKey` | |
| `addr` | `[Interface] Address` | **IPv4 part only**, for example `10.2.0.2/32` |
| `pub` | `[Peer] PublicKey` | |
| `psk` | `[Peer] PresharedKey` | `""` if your provider doesn't give one |
| `host` | `[Peer] Endpoint` before the `:` | IP or hostname |
| `port` | `[Peer] Endpoint` after the `:` | Number, no quotes |
| `mtu` | — | Keep `1280` |

Add as many lines as you like, one per server.

### 6.3 Switch server (one line)

```routeros
:global WGPick "proton-nl"; /system script run WG-Apply
```

`WG-Apply` loads the profile onto `wg-commercial`, replaces the peer, removes **all** old tunnel addresses and adds the new one, then saves the choice into WG-Profiles (`WGActive`) so it survives reboots. You can also edit `WGActive` in WG-Profiles by hand and run `WG-Apply`.

### 6.4 Check it worked

```routeros
/system script run FO-Status
```

`last handshake` should show a few seconds ago. If it says `never`, check the key, endpoint and port.

> 🔐 Profile keys are stored in the script text. Anyone with a router login that can read scripts can see them, so keep router accounts to people you trust.

---

## 7. Daily use

| Task | How |
| --- | --- |
| See everything at a glance | `/system script run FO-Status` (from WebFig **Run Script**, the result is in **Log**) |
| Pause / resume the VPN | Run **FO-VPN-Toggle**. While paused, the auto shield won't turn it back on, even after a reboot |
| Switch VPN server | `:global WGPick "name"; /system script run WG-Apply` |
| Save the live VPN as a profile | `:global WGImportName "name"; /system script run WG-Import` |
| Change any setting | Edit **Starlink-Settings** → run **FO-Apply** |
| Watch switching live | **Log**, filter `FO` |

### Test the failover without touching cables

```routeros
# Simulate Starlink failing (the probe pings into the blackhole)
/ip route disable [find comment="FO-Starlink-Monitor"]
# ...watch the Log, then simulate recovery
/ip route enable [find comment="FO-Starlink-Monitor"]
```

Expect `FO: Starlink lost, now on MTN` within about a second, and `FO: Starlink stable, back on Starlink` about `FOHoldSec` + 1 seconds after you re-enable it.

---

## 8. Captive Portal (Voucher System)

v2 handles the Hotspot/VPN conflict automatically. With `FOHotspot "auto"`, `FO-Apply` adds `hotspot=auth` to the shield rule whenever a Hotspot server exists, so unauthenticated users see the login page before their traffic enters the tunnel. **After you create (or remove) the Hotspot, run `FO-Apply` once.**

### Step 1: Configure the Hotspot

1. **IP → Hotspot → Servers → Hotspot Setup**.
2. Follow the wizard:
   - **Hotspot Interface:** `bridge`
   - **Local Address:** leave the default, and leave "Masquerade Network" checked
   - **Certificate:** `none`
   - **IP Address of SMTP Server:** `0.0.0.0`
   - **DNS Servers:** `8.8.8.8` and `1.1.1.1`
   - **DNS Name:** for example `wifi.local`
   - **Local Hotspot User:** create a master bypass admin account
3. Run **FO-Apply**.

### Step 2: Generate vouchers

A voucher is a Hotspot user on a user profile.

1. **IP → Hotspot → User Profiles**: set bandwidth limits (for example `5M/5M`) and `Shared Users: 1`.
2. Generate codes with REST API pushes to `/rest/ip/hotspot/user`, or link the router to **Mikhmon** for bulk PDF printing.

---

## 9. System Monitoring & GUI Graphs

- **Connected devices (IPs and hostnames):** **IP → DHCP Server → Leases**.
- **Wi-Fi signal strength:** **Wireless → Registration**.
- **Real-time bandwidth:** **Interfaces**, double-click a port (Starlink, MTN or `bridge`), **Traffic** tab.
- **Historical graphs (daily/monthly):** **Tools → Graphing → Interface Rules → Add New**, leave interface `all`, then open `http://192.168.88.1/graphs/`.

---

## 10. Troubleshooting

| Symptom | Check |
| --- | --- |
| `FO-Status` says probe `unknown` | Normal for about 30s after a reboot or `FO-Apply` |
| Probe always `down`, Starlink works | **IP → Routes**: `FO-Starlink-Monitor` gateway must equal the Starlink DHCP gateway. Re-plug the Starlink cable to force a new lease |
| Constant switching while `/ping 9.9.9.9` looks clean | Loosen `FOProbeLoss` / `FOProbeMaxAvg`. Some 7.21.x builds had Netwatch ICMP false alarms, so check the changelog if this persists after an update |
| No internet when the shield is ON | Tunnel down: `FO-Status` shows the last handshake. Switch profile, or pause with `FO-VPN-Toggle` |
| Hotspot login page doesn't appear | Run `FO-Apply` after creating the Hotspot (adds `hotspot=auth`) |
| Import stops with an error | Re-run with `verbose=yes`, and note the line it stopped on |
| `not enough permissions` in Log | Re-import the installer; don't change script or scheduler policies |
| WG-Import says no interface / peer / address | Check `FOWGIf` in Starlink-Settings matches your tunnel name (**WireGuard** menu) |

---

## 11. Object reference

Everything v2 creates (comments or names):

- **Scripts:** `Starlink-Settings`, `WG-Profiles`, `FO-Apply`, `FO-Ports`, `FO-Brain`, `FO-Cooldown`, `FO-Boot`, `FO-Status`, `FO-VPN-Toggle`, `WG-Apply`, `WG-Import` (plus `WG-Profiles-backup` after an import)
- **Schedulers:** `FO-Boot` (startup), `FO-Brain` (1s), `FO-Cooldown` (`FOFlapWindow`)
- **Netwatch:** `FO-Probe`
- **Routes:** `FO-Starlink-Main`, `FO-Starlink-Monitor`, `FO-Monitor-Blackhole`, `FO-VPN-Default` (table `VPN`)
- **DHCP clients:** `FO-Starlink`, `FO-MTN`
- **Firewall:** mangle `FO-VPN-Shield`, `FO-MSS` ×2; NAT `FO-VPN-NAT`; address list `FO-Local`
- **Global variables:** `FO*`, `WGProfiles`, `WGActive`, `WGPick`, `WGImportName`

**Where to add your own exceptions:** add an address to the `FO-Local` address list (**IP → Firewall → Address Lists**) to keep it out of the VPN. Entries you add yourself are never touched by `FO-Apply`.

---

## Appendix A: Script sources

These are the exact scripts the installer creates. Use them to read what each one does, or to create the scripts by hand in **System → Scripts → Add New** (name, tick the policies shown, paste the source) if you can't use `/import`. For a manual setup, also create **WG-Profiles** (policies `read, write, policy, test`) from the template in Appendix B, then run `FO-Apply` and `FO-Boot`.

{{APPENDIX}}

## Appendix B: WG-Profiles template

```routeros
{{WGTEMPLATE}}
```
