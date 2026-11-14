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

### A.1 Starlink-Settings

Policies: `read, write, policy, test`

```routeros
# ================================================================
#  STARLINK / MTN FAILOVER SETTINGS  (FO v2)
#  1. Change the values below.  2. Run the FO-Apply script.
#  Keep the quotes where they are. Lines starting with # are notes.
# ================================================================

# ---- Ports -------------------------------------------------------
# Port the Starlink Mini is plugged into
:global FOStarlinkPort "ether1"
# Port the MTN 4G router is plugged into
:global FOMTNPort "ether2"
# LAN bridge (a port that stops being WAN is put back here)
:global FOLANBridge "bridge"
# LAN subnet (never sent into the VPN)
:global FOLANSubnet "192.168.88.0/24"

# ---- Starlink sensor (ping stream through Starlink only) ---------
# Do NOT use this host as a DNS server
:global FOMonitorHost "9.9.9.9"
# A new burst of pings starts this often
:global FOProbeInterval "1s"
# Pings per burst, and the gap between them
:global FOProbeCount 5
:global FOProbeSpacing "100ms"
# How long to wait for each reply
:global FOProbeTimeout "500ms"
# Starlink counts as DOWN when loss in a burst passes this percent...
:global FOProbeLoss 50
# ...or when the average ping goes above this
:global FOProbeMaxAvg "300ms"

# ---- Switching ---------------------------------------------------
# Seconds Starlink must stay healthy before traffic moves back
:global FOHoldSec 2
# Route distance of the MTN backup route (must be above 1)
:global FOMTNDistance 2

# ---- VPN shield --------------------------------------------------
# "auto"   = turn on after FOFlapLimit drops within FOFlapWindow
# "always" = keep LAN traffic in the VPN all the time
# "off"    = never put LAN traffic in the VPN
:global FOShieldMode "auto"
:global FOFlapLimit 2
:global FOFlapWindow "10m"
# WireGuard interface used by the shield
:global FOWGIf "wg-commercial"
# TCP MSS inside the tunnel (MTU 1280 -> 1240)
:global FOMSS 1240
# Captive portal support: "auto" (detect Hotspot), "yes" or "no"
:global FOHotspot "auto"

# ---- DNS ---------------------------------------------------------
:global FODNS "8.8.8.8,1.1.1.1"
```

### A.2 FO-Ports

Policies: `read, write, policy, test`

```routeros
# FO-Ports: makes FOStarlinkPort and FOMTNPort the two WAN ports.
# A port that used to be WAN and no longer is goes back to the LAN bridge.
# Run it on WiFi (or a LAN port you are NOT changing).
/system script run Starlink-Settings
:global FOStarlinkPort; :global FOMTNPort; :global FOMTNDistance; :global FOLANBridge

:local sl $FOStarlinkPort
:local mt $FOMTNPort
:if ($sl = $mt) do={ :error "FO-Ports: Starlink and MTN must use different ports" }
:foreach p in=[:toarray ($sl . "," . $mt)] do={
  :if ([:len [/interface find name=$p]] = 0) do={ :error ("FO-Ports: there is no interface called " . $p) }
}

# Which ports were WAN before?
:local oldS ""
:local oldM ""
:foreach c in=[/ip dhcp-client find comment="FO-Starlink"] do={ :set oldS [/ip dhcp-client get $c interface] }
:foreach c in=[/ip dhcp-client find comment="FO-MTN"] do={ :set oldM [/ip dhcp-client get $c interface] }
:local changed (($oldS != $sl) || ($oldM != $mt))

# 1. Give retired WAN ports back to the LAN
:foreach p in=[:toarray ($oldS . "," . $oldM)] do={
  :if ($p != "" && $p != $sl && $p != $mt) do={
    /interface list member remove [find list="WAN" interface=$p]
    :if ([:len [/interface bridge port find interface=$p]] = 0) do={
      /interface bridge port add bridge=$FOLANBridge interface=$p comment="FO-released"
    }
    :log warning ("FO-Ports: " . $p . " is a LAN port again")
  }
}

# 2. Take the WAN ports out of the LAN and into the WAN list
:foreach p in=[:toarray ($sl . "," . $mt)] do={
  /interface bridge port remove [find interface=$p]
  :if ([:len [/interface list member find list="WAN" interface=$p]] = 0) do={
    /interface list member add list="WAN" interface=$p
  }
}

# 3. DHCP clients. Starlink keeps our routes pointed at its live gateway.
:local slScript ":if (\$bound=1) do={ /ip route set [find comment~\"^FO-Starlink-\"] gateway=\$\"gateway-address\" }"
:if ($changed) do={
  /ip dhcp-client remove [find comment="FO-Starlink"]
  /ip dhcp-client remove [find comment="FO-MTN"]
  /ip dhcp-client remove [find interface=$sl]
  /ip dhcp-client remove [find interface=$mt]
  /ip dhcp-client add interface=$sl add-default-route=no use-peer-dns=no use-peer-ntp=no script=$slScript comment="FO-Starlink"
  /ip dhcp-client add interface=$mt add-default-route=yes default-route-distance=$FOMTNDistance use-peer-dns=no use-peer-ntp=no comment="FO-MTN"
  :log warning ("FO-Ports: Starlink=" . $sl . " MTN=" . $mt)
} else={
  /ip dhcp-client set [find comment="FO-Starlink"] add-default-route=no script=$slScript
  /ip dhcp-client set [find comment="FO-MTN"] default-route-distance=$FOMTNDistance
}
```

### A.3 FO-Apply

Policies: `read, write, policy, test`

```routeros
# FO-Apply: applies everything in Starlink-Settings. Safe to run any time.
/system script run Starlink-Settings
:global FOStarlinkPort; :global FOMTNPort; :global FOLANSubnet; :global FOMonitorHost
:global FOProbeInterval; :global FOProbeCount; :global FOProbeSpacing; :global FOProbeTimeout
:global FOProbeLoss; :global FOProbeMaxAvg; :global FOHoldSec; :global FOShieldMode; :global FOFlapWindow
:global FOWGIf; :global FOMSS; :global FOHotspot; :global FODNS
:global FOState; :global FOUpTicks; :global FOFlaps

# 1. Ports and DHCP clients
/system script run FO-Ports

# 2. Starlink gateway: from DHCP, else the existing route, else the Starlink default
#    (waits up to 5s for a fresh DHCP lease after a port change)
:local n 0
:do {
  :while ($n < 10 && [/ip dhcp-client get [:pick [/ip dhcp-client find comment="FO-Starlink"] 0] status] != "bound") do={ :delay 500ms; :set n ($n + 1) }
} on-error={}
:local gw ""
:do { :set gw [:tostr [/ip dhcp-client get [:pick [/ip dhcp-client find comment="FO-Starlink"] 0] gateway]] } on-error={}
:if ($gw = "") do={ :do { :set gw [:tostr [/ip route get [:pick [/ip route find comment="FO-Starlink-Main"] 0] gateway]] } on-error={} }
:if ($gw = "") do={ :set gw "192.168.1.1" }

# 3. Routes. The monitor host can only ever be reached through Starlink.
:if ([:len [/ip route find comment="FO-Starlink-Main"]] = 0) do={
  /ip route add dst-address=0.0.0.0/0 gateway=$gw distance=1 comment="FO-Starlink-Main"
}
/ip route remove [find comment="FO-Starlink-Monitor"]
/ip route remove [find comment="FO-Monitor-Blackhole"]
/ip route add dst-address=($FOMonitorHost . "/32") gateway=$gw distance=1 comment="FO-Starlink-Monitor"
/ip route add dst-address=($FOMonitorHost . "/32") blackhole distance=10 comment="FO-Monitor-Blackhole"

# 4. Sensor. Netwatch pulls the Starlink route itself the moment a burst fails.
/tool netwatch remove [find comment="FO-Probe"]
:local down (":if ([/interface get [find name=\"" . $FOMTNPort . "\"] running]) do={ /ip route disable [find comment=\"FO-Starlink-Main\"] }")
/tool netwatch add host=$FOMonitorHost type=icmp interval=$FOProbeInterval timeout=$FOProbeTimeout \
  packet-count=$FOProbeCount packet-interval=$FOProbeSpacing thr-loss-percent=$FOProbeLoss thr-avg=$FOProbeMaxAvg \
  early-failure-detection=yes startup-delay=30s up-script="" down-script=$down comment="FO-Probe"

# 5. VPN plumbing
:local wg $FOWGIf
:if ([:len [/interface wireguard find name=$wg]] = 0) do={ /interface wireguard add name=$wg mtu=1280 comment="FO-WG" }
:if ([:len [/routing table find name="VPN"]] = 0) do={ /routing table add name=VPN fib }
/ip route remove [find comment="FO-VPN-Default"]
/ip route add dst-address=0.0.0.0/0 gateway=$wg routing-table=VPN comment="FO-VPN-Default"
/ip firewall nat remove [find comment="FO-VPN-NAT"]
/ip firewall nat add chain=srcnat out-interface=$wg action=masquerade comment="FO-VPN-NAT"

# Local networks that never go into the VPN (add your own to list FO-Local)
/ip firewall address-list remove [find list="FO-Local" comment="FO-Setting"]
/ip firewall address-list add list="FO-Local" address=$FOLANSubnet comment="FO-Setting"

# MSS clamp only for tunnel traffic, so direct traffic keeps full speed
/ip firewall mangle remove [find comment="FO-MSS"]
:local mssRange (($FOMSS + 1) . "-65535")
/ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn out-interface=$wg tcp-mss=$mssRange action=change-mss new-mss=$FOMSS passthrough=yes comment="FO-MSS"
/ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn in-interface=$wg tcp-mss=$mssRange action=change-mss new-mss=$FOMSS passthrough=yes comment="FO-MSS"

# Shield rule (rebuilt, keeps its current on/off state)
:local on false
:foreach r in=[/ip firewall mangle find comment="FO-VPN-Shield"] do={
  :if ([/ip firewall mangle get $r disabled] = false) do={ :set on true }
}
/ip firewall mangle remove [find comment="FO-VPN-Shield"]
:local hs false
:if ($FOHotspot = "yes") do={ :set hs true }
:if ($FOHotspot = "auto" && [:len [/ip hotspot find]] > 0) do={ :set hs true }
:if ($hs) do={
  /ip firewall mangle add chain=prerouting src-address-list=FO-Local dst-address-list=!FO-Local hotspot=auth \
    action=mark-routing new-routing-mark=VPN passthrough=yes disabled=yes comment="FO-VPN-Shield"
} else={
  /ip firewall mangle add chain=prerouting src-address-list=FO-Local dst-address-list=!FO-Local \
    action=mark-routing new-routing-mark=VPN passthrough=yes disabled=yes comment="FO-VPN-Shield"
}
:local wgOn ([/interface wireguard get [:pick [/interface wireguard find name=$wg] 0] disabled] = false)
:if ($FOShieldMode = "always") do={ :set on true }
:if ($FOShieldMode = "off" || $wgOn = false) do={ :set on false }
:if ($on) do={ /ip firewall mangle enable [find comment="FO-VPN-Shield"] }

# FastTrack skips mangle rules, so it stays off
/ip firewall filter disable [find action="fasttrack-connection"]

# 6. DNS
/ip dns set servers=$FODNS allow-remote-requests=yes

# 7. Schedulers (added once, then only the cooldown interval is updated)
:if ([:len [/system scheduler find name="FO-Boot"]] = 0) do={
  /system scheduler add name="FO-Boot" start-time=startup interval=0 on-event="FO-Boot" policy=read,write,policy,test
}
:if ([:len [/system scheduler find name="FO-Brain"]] = 0) do={
  /system scheduler add name="FO-Brain" start-date=[/system clock get date] start-time=[/system clock get time] interval=1s on-event="FO-Brain" policy=read,write,policy,test
}
:if ([:len [/system scheduler find name="FO-Cooldown"]] = 0) do={
  /system scheduler add name="FO-Cooldown" start-date=[/system clock get date] start-time=[/system clock get time] interval=$FOFlapWindow on-event="FO-Cooldown" policy=read,write,policy,test
} else={
  /system scheduler set [find name="FO-Cooldown"] interval=$FOFlapWindow
}

# 8. Fresh runtime state
:set FOState "up"
:set FOUpTicks 0
:if ([:typeof $FOFlaps] = "nothing") do={ :set FOFlaps 0 }
/ip route enable [find comment="FO-Starlink-Main"]
:log warning ("FO-Apply: done. Starlink=" . $FOStarlinkPort . " MTN=" . $FOMTNPort . " hold=" . $FOHoldSec . "s shield=" . $FOShieldMode)
```

### A.4 FO-Brain

Policies: `read, write, policy, test`

```routeros
# FO-Brain: runs every second. Netwatch does the fast cut-over;
# this handles the switch back, MTN loss and the VPN shield.
:global FOMTNPort; :global FOHoldSec; :global FOShieldMode; :global FOFlapLimit; :global FOWGIf
:global FOState; :global FOUpTicks; :global FOFlaps
:if ([:typeof $FOHoldSec] = "nothing") do={ /system script run Starlink-Settings }
:if ([:typeof $FOState] = "nothing") do={ :set FOState "up"; :set FOUpTicks 0; :set FOFlaps 0 }

:local nw [/tool netwatch get [find comment="FO-Probe"] status]
:local rt [:pick [/ip route find comment="FO-Starlink-Main"] 0]
:local rtOff [/ip route get $rt disabled]
:local mtn [/interface get [find name=$FOMTNPort] running]

# MTN cable/link gone: never keep traffic off Starlink with nowhere to go
:if ($rtOff && !$mtn) do={
  /ip route enable $rt
  :set rtOff false
  :log warning "FO: MTN link down, Starlink route restored"
}

# Backup in case a burst failed between Netwatch runs
:if ($nw = "down") do={
  :set FOUpTicks 0
  :if ($mtn && !$rtOff) do={ /ip route disable $rt; :set rtOff true }
}

# New drop
:if ($FOState = "up" && ($nw = "down" || $rtOff)) do={
  :set FOState "down"
  :set FOFlaps ($FOFlaps + 1)
  :local via "MTN"
  :if (!$mtn) do={ :set via "nothing (MTN link down)" }
  :log warning ("FO: Starlink lost, now on " . $via . ". Drops this window: " . $FOFlaps)
  :if ($FOShieldMode = "auto" && $FOFlaps >= $FOFlapLimit) do={
    :if ([/interface wireguard get [find name=$FOWGIf] disabled]) do={
      :log warning "FO: VPN shield skipped (VPN paused)"
    } else={
      /ip firewall mangle enable [find comment="FO-VPN-Shield"]
      :log warning "FO: VPN shield ON"
    }
  }
}

# Recovery: Starlink must pass FOHoldSec checks in a row
:if ($FOState = "down" && $nw = "up") do={
  :set FOUpTicks ($FOUpTicks + 1)
  :if ($FOUpTicks >= $FOHoldSec) do={
    /ip route enable $rt
    :set FOState "up"
    :set FOUpTicks 0
    :log warning "FO: Starlink stable, back on Starlink"
  }
}
```

### A.5 FO-Cooldown

Policies: `read, write, policy, test`

```routeros
# FO-Cooldown: runs every FOFlapWindow. Turns the auto shield off after a quiet window.
:global FOFlaps; :global FOFlapLimit; :global FOShieldMode
:if ($FOShieldMode = "auto" && [:tonum $FOFlaps] < [:tonum $FOFlapLimit]) do={
  :if ([:len [/ip firewall mangle find comment="FO-VPN-Shield" disabled=no]] > 0) do={
    /ip firewall mangle disable [find comment="FO-VPN-Shield"]
    :log warning "FO: quiet window, VPN shield OFF"
  }
}
:set FOFlaps 0
```

### A.6 FO-Boot

Policies: `read, write, policy, test`

```routeros
# FO-Boot: runs once at startup. Loads settings and starts on Starlink.
/system script run Starlink-Settings
/system script run WG-Profiles
:global FOState "up"
:global FOUpTicks 0
:global FOFlaps 0
/ip route enable [find comment="FO-Starlink-Main"]
:log info "FO: boot init done"
```

### A.7 FO-VPN-Toggle

Policies: `read, write, policy, test`

```routeros
# FO-VPN-Toggle: pause or resume the VPN.
# While paused, the auto shield will not switch it back on (survives reboot).
:global FOWGIf; :global FOShieldMode
:if ([:typeof $FOWGIf] = "nothing") do={ /system script run Starlink-Settings }
:local i [:pick [/interface wireguard find name=$FOWGIf] 0]
:if ([/interface wireguard get $i disabled]) do={
  /interface wireguard enable $i
  :if ($FOShieldMode != "off") do={ /ip firewall mangle enable [find comment="FO-VPN-Shield"] }
  :log warning "FO: VPN resumed (shield on, auto mode active)"
} else={
  /interface wireguard disable $i
  /ip firewall mangle disable [find comment="FO-VPN-Shield"]
  :log warning "FO: VPN paused (auto shield suspended)"
}
```

### A.8 FO-Status

Policies: `read, write, policy, test`

```routeros
# FO-Status: one-screen summary. Prints in Terminal and writes to the Log
# (so it also works from WebFig "Run Script").
:global FOStarlinkPort; :global FOMTNPort; :global FOShieldMode; :global FOWGIf; :global FOHoldSec
:global FOFlaps; :global WGActive; :global WGProfiles
:if ([:typeof $FOWGIf] = "nothing") do={ /system script run Starlink-Settings }
:if ([:typeof $WGActive] = "nothing") do={ /system script run WG-Profiles }
:local out do={ :put $1; :log info ("FO-Status: " . $1) }

:local nw [/tool netwatch get [find comment="FO-Probe"] status]
:local wan "Starlink"
:if ([/ip route get [find comment="FO-Starlink-Main"] disabled]) do={ :set wan "MTN (backup)" }
:local sh "OFF"
:if ([:len [/ip firewall mangle find comment="FO-VPN-Shield" disabled=no]] > 0) do={ :set sh "ON" }
:local hsk "never"
:foreach p in=[/interface wireguard peers find interface=$FOWGIf] do={
  :local h [/interface wireguard peers get $p last-handshake]
  :if ([:typeof $h] != "nil" && [:typeof $h] != "nothing") do={ :set hsk ([:tostr $h] . " ago") }
}
:local names ""
:foreach k,v in=$WGProfiles do={ :set names ($names . $k . " ") }

$out ("Internet via    : " . $wan)
$out ("Starlink probe  : " . $nw . " on " . $FOStarlinkPort)
$out ("MTN link        : " . [/interface get [find name=$FOMTNPort] running] . " on " . $FOMTNPort)
$out ("Switch-back     : after " . $FOHoldSec . "s healthy")
$out ("VPN shield      : " . $sh . " (mode " . $FOShieldMode . ")")
$out ("VPN paused      : " . [/interface wireguard get [find name=$FOWGIf] disabled])
$out ("VPN profile     : " . $WGActive . ", last handshake " . $hsk)
$out ("Profiles        : " . $names)
$out ("Drops in window : " . $FOFlaps)
```

### A.9 WG-Apply

Policies: `read, write, policy, test, sensitive`

```routeros
# WG-Apply: loads a profile from WG-Profiles onto the VPN interface.
#   Use the WGActive profile:   /system script run WG-Apply
#   Switch to another one:      :global WGPick "proton-nl"; /system script run WG-Apply
# A pick is saved back into WG-Profiles, so it survives reboots.
/system script run WG-Profiles
:global WGProfiles; :global WGActive; :global WGPick; :global FOWGIf
:if ([:typeof $FOWGIf] = "nothing") do={ /system script run Starlink-Settings }

:local name $WGActive
:if ([:typeof $WGPick] = "str") do={ :if ($WGPick != "") do={ :set name $WGPick } }
:set WGPick ""
:local p ($WGProfiles->$name)
:if ([:typeof $p] != "array") do={ :error ("WG-Apply: no profile called '" . $name . "'") }
:local mtu ($p->"mtu")
:if ([:typeof $mtu] = "nothing") do={ :set mtu 1280 }
:local psk ($p->"psk")
:if ([:typeof $psk] = "nothing") do={ :set psk "" }

:local wg $FOWGIf
:if ([:len [/interface wireguard find name=$wg]] = 0) do={ /interface wireguard add name=$wg }
/interface wireguard set [find name=$wg] private-key=($p->"priv") mtu=$mtu
/interface wireguard peers remove [find interface=$wg]
/interface wireguard peers add interface=$wg public-key=($p->"pub") endpoint-address=($p->"host") \
  endpoint-port=($p->"port") allowed-address=0.0.0.0/0 persistent-keepalive=25s comment=("FO-WG " . $name)
:if ($psk != "") do={ /interface wireguard peers set [find interface=$wg] preshared-key=$psk }

# Exactly one address on the tunnel (stale /32s break return traffic)
/ip address remove [find interface=$wg]
/ip address add address=($p->"addr") interface=$wg comment=("FO-WG " . $name)

# Save the choice into WG-Profiles
:if ($name != $WGActive) do={
  :local key ":global WGActive \""
  :local src [/system script get [find name="WG-Profiles"] source]
  :local a [:find $src $key]
  :if ([:typeof $a] = "num") do={
    :local s ($a + [:len $key])
    :local e ($s + [:len $WGActive])
    :if ([:pick $src $s $e] = $WGActive) do={
      /system script set [find name="WG-Profiles"] source=([:pick $src 0 $s] . $name . [:pick $src $e [:len $src]])
    }
  }
  :set WGActive $name
}
:log warning ("WG-Apply: VPN now uses profile " . $name)
```

### A.10 WG-Import

Policies: `read, write, policy, test, sensitive`

```routeros
# WG-Import: saves the WireGuard config that is live on the router as a
# profile in WG-Profiles and makes it the active one. Other profiles are kept.
#   Save as "current":       /system script run WG-Import
#   Save under a name:       :global WGImportName "mullvad-lon"; /system script run WG-Import
:global FOWGIf; :global WGImportName; :global WGProfiles; :global WGActive
:if ([:len [/system script find name="Starlink-Settings"]] > 0) do={ /system script run Starlink-Settings }
:local wg $FOWGIf
:if ([:typeof $wg] != "str" || $wg = "") do={ :set wg "wg-commercial" }
:local name "current"
:if ([:typeof $WGImportName] = "str") do={ :if ($WGImportName != "") do={ :set name $WGImportName } }
:set WGImportName ""
:if ([:typeof [:find $name "\""]] = "num" || [:typeof [:find $name "\\"]] = "num") do={ :error "WG-Import: the profile name cannot contain quotes or backslashes" }

# 1. Read the live config
:local i [:pick [/interface wireguard find name=$wg] 0]
:if ([:typeof $i] = "nil") do={ :error ("WG-Import: there is no WireGuard interface called " . $wg) }
:local peers [/interface wireguard peers find interface=$wg]
:if ([:len $peers] = 0) do={ :error ("WG-Import: " . $wg . " has no peer to import") }
:if ([:len $peers] > 1) do={ :log warning ("WG-Import: " . $wg . " has " . [:len $peers] . " peers, importing the first one") }
:local pr [:pick $peers 0]
:local ads [/ip address find interface=$wg]
:if ([:len $ads] = 0) do={ :error ("WG-Import: " . $wg . " has no IPv4 address to import") }
# Newest address = the one added last (older ones are usually stale)
:local ad [:pick $ads ([:len $ads] - 1)]
:if ([:len $ads] > 1) do={
  :local all ""
  :foreach a in=$ads do={ :set all ($all . [/ip address get $a address] . " ") }
  :log warning ("WG-Import: several tunnel addresses (" . $all . "), using " . [/ip address get $ad address] . ". Check it, then run WG-Apply to remove the others")
}
:local psk [/interface wireguard peers get $pr preshared-key]
:if ([:typeof $psk] != "str") do={ :set psk "" }
:local prof [:toarray ""]
:set ($prof->"priv") [/interface wireguard get $i private-key]
:set ($prof->"pub") [/interface wireguard peers get $pr public-key]
:set ($prof->"psk") $psk
:set ($prof->"addr") [:tostr [/ip address get $ad address]]
:set ($prof->"host") [:tostr [/interface wireguard peers get $pr endpoint-address]]
:set ($prof->"port") [/interface wireguard peers get $pr endpoint-port]
:set ($prof->"mtu") [/interface wireguard get $i mtu]

# 2. Merge with the existing profiles
:local old ""
:if ([:len [/system script find name="WG-Profiles"]] > 0) do={
  :set old [/system script get [find name="WG-Profiles"] source]
  /system script run WG-Profiles
}
:if ([:typeof $WGProfiles] != "array") do={ :set WGProfiles [:toarray ""] }
:set ($WGProfiles->$name) $prof

# 3. Rewrite WG-Profiles (one line per profile)
:local body ""
:foreach k,v in=$WGProfiles do={
  :local mtu ($v->"mtu")
  :if ([:typeof $mtu] = "nothing") do={ :set mtu 1280 }
  :local pk ($v->"psk")
  :if ([:typeof $pk] = "nothing") do={ :set pk "" }
  :set body ($body . ":set (\$WGProfiles->\"" . $k . "\") {\"priv\"=\"" . ($v->"priv") . "\";\"pub\"=\"" . ($v->"pub") . "\";\"psk\"=\"" . $pk . "\";\"addr\"=\"" . ($v->"addr") . "\";\"host\"=\"" . ($v->"host") . "\";\"port\"=" . ($v->"port") . ";\"mtu\"=" . $mtu . "}\n")
}
:local head "# ================================================================\n#  WIREGUARD PROFILES (FO v2)\n#  One :set line per VPN server. Copy the example line, remove the #,\n#  give it a name and paste the values from your provider's .conf:\n#    priv = [Interface] PrivateKey     addr = [Interface] Address (IPv4 only)\n#    pub  = [Peer] PublicKey           host = Endpoint IP (before the :)\n#    psk  = [Peer] PresharedKey or \"\"  port = Endpoint port (after the :)\n#    mtu  = 1280\n#  Switch server:  :global WGPick \"name\"; /system script run WG-Apply\n# ================================================================\n:global WGProfiles [:toarray \"\"]\n"
:local ex "#:set (\$WGProfiles->\"example\") {\"priv\"=\"PRIVATE_KEY\";\"pub\"=\"SERVER_PUBLIC_KEY\";\"psk\"=\"\";\"addr\"=\"10.2.0.2/32\";\"host\"=\"203.0.113.10\";\"port\"=51820;\"mtu\"=1280}\n"
:local tail "\n# Profile WG-Apply uses when no pick is given\n:global WGActive \""
:local src ($head . $body . $ex . $tail . $name . "\"\n")
:if ($old != "") do={
  /system script remove [find name="WG-Profiles-backup"]
  /system script add name="WG-Profiles-backup" policy=read source=("# Copy of WG-Profiles before WG-Import. Not used by anything; delete when happy.\n" . $old)
  /system script set [find name="WG-Profiles"] source=$src
} else={
  /system script add name="WG-Profiles" policy=read,write,policy,test source=$src
}
:set WGActive $name
:log warning ("WG-Import: saved " . $wg . " as profile '" . $name . "' (endpoint " . ($prof->"host") . ":" . ($prof->"port") . ", address " . ($prof->"addr") . ")")
:put ("Saved " . $wg . " as WireGuard profile '" . $name . "'. Address " . ($prof->"addr") . ", endpoint " . ($prof->"host") . ":" . ($prof->"port"))
```


## Appendix B: WG-Profiles template

```routeros
# ================================================================
#  WIREGUARD PROFILES (FO v2)
#  One :set line per VPN server. Copy the example line, remove the #,
#  give it a name and paste the values from your provider's .conf:
#    priv = [Interface] PrivateKey     addr = [Interface] Address (IPv4 only)
#    pub  = [Peer] PublicKey           host = Endpoint IP (before the :)
#    psk  = [Peer] PresharedKey or ""  port = Endpoint port (after the :)
#    mtu  = 1280
#  Switch server:  :global WGPick "name"; /system script run WG-Apply
# ================================================================
:global WGProfiles [:toarray ""]
:set ($WGProfiles->"current") {"priv"="PRIVATE_KEY";"pub"="SERVER_PUBLIC_KEY";"psk"="";"addr"="10.64.0.2/32";"host"="203.0.113.20";"port"=51820;"mtu"=1280}
#:set ($WGProfiles->"example") {"priv"="PRIVATE_KEY";"pub"="SERVER_PUBLIC_KEY";"psk"="";"addr"="10.2.0.2/32";"host"="203.0.113.10";"port"=51820;"mtu"=1280}

# Profile WG-Apply uses when no pick is given
:global WGActive "current"
```
