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
