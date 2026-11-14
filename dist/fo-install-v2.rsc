# ================================================================
#  FO v2 INSTALLER: Starlink/MTN failover + VPN shield (RouterOS 7.24+)
#  Run fo-cleanup-v1.rsc first if you used the v1 manual.
#  Import:  /import file-name=fo-install-v2.rsc
#  Safe to re-import: your Starlink-Settings and WG-Profiles are kept.
# ================================================================
:log warning "FO v2: install started"

# 1. Lock the bridge MAC (one time) so the LAN MAC never changes with ports
{ :foreach b in=[/interface bridge find name="bridge"] do={
  :if ([/interface bridge get $b auto-mac]) do={ /interface bridge set $b auto-mac=no admin-mac=[/interface bridge get $b mac-address] } } }

# 2. Program scripts (always replaced with this version)
/system script remove [find name="FO-Ports"]
/system script add name="FO-Ports" policy=read,write,policy,test dont-require-permissions=no source="# FO-Ports: makes FOStarlinkPort and FOMTNPort the two WAN ports.\n\
    # A port that used to be WAN and no longer is goes back to the LAN bridge.\n\
    # Run it on WiFi (or a LAN port you are NOT changing).\n\
    /system script run Starlink-Settings\n\
    :global FOStarlinkPort; :global FOMTNPort; :global FOMTNDistance; :global FOLANBridge\n\
    \n\
    :local sl \$FOStarlinkPort\n\
    :local mt \$FOMTNPort\n\
    :if (\$sl = \$mt) do={ :error \"FO-Ports: Starlink and MTN must use different ports\" }\n\
    :foreach p in=[:toarray (\$sl . \",\" . \$mt)] do={\n\
      :if ([:len [/interface find name=\$p]] = 0) do={ :error (\"FO-Ports: there is no interface called \" . \$p) }\n\
    }\n\
    \n\
    # Which ports were WAN before\?\n\
    :local oldS \"\"\n\
    :local oldM \"\"\n\
    :foreach c in=[/ip dhcp-client find comment=\"FO-Starlink\"] do={ :set oldS [/ip dhcp-client get \$c interface] }\n\
    :foreach c in=[/ip dhcp-client find comment=\"FO-MTN\"] do={ :set oldM [/ip dhcp-client get \$c interface] }\n\
    :local changed ((\$oldS != \$sl) || (\$oldM != \$mt))\n\
    \n\
    # 1. Give retired WAN ports back to the LAN\n\
    :foreach p in=[:toarray (\$oldS . \",\" . \$oldM)] do={\n\
      :if (\$p != \"\" && \$p != \$sl && \$p != \$mt) do={\n\
        /interface list member remove [find list=\"WAN\" interface=\$p]\n\
        :if ([:len [/interface bridge port find interface=\$p]] = 0) do={\n\
          /interface bridge port add bridge=\$FOLANBridge interface=\$p comment=\"FO-released\"\n\
        }\n\
        :log warning (\"FO-Ports: \" . \$p . \" is a LAN port again\")\n\
      }\n\
    }\n\
    \n\
    # 2. Take the WAN ports out of the LAN and into the WAN list\n\
    :foreach p in=[:toarray (\$sl . \",\" . \$mt)] do={\n\
      /interface bridge port remove [find interface=\$p]\n\
      :if ([:len [/interface list member find list=\"WAN\" interface=\$p]] = 0) do={\n\
        /interface list member add list=\"WAN\" interface=\$p\n\
      }\n\
    }\n\
    \n\
    # 3. DHCP clients. Starlink keeps our routes pointed at its live gateway.\n\
    :local slScript \":if (\\\$bound=1) do={ /ip route set [find comment~\\\"^FO-Starlink-\\\"] gateway=\\\$\\\"gateway-address\\\" }\"\n\
    :if (\$changed) do={\n\
      /ip dhcp-client remove [find comment=\"FO-Starlink\"]\n\
      /ip dhcp-client remove [find comment=\"FO-MTN\"]\n\
      /ip dhcp-client remove [find interface=\$sl]\n\
      /ip dhcp-client remove [find interface=\$mt]\n\
      /ip dhcp-client add interface=\$sl add-default-route=no use-peer-dns=no use-peer-ntp=no script=\$slScript comment=\"FO-Starlink\"\n\
      /ip dhcp-client add interface=\$mt add-default-route=yes default-route-distance=\$FOMTNDistance use-peer-dns=no use-peer-ntp=no comment=\"FO-MTN\"\n\
      :log warning (\"FO-Ports: Starlink=\" . \$sl . \" MTN=\" . \$mt)\n\
    } else={\n\
      /ip dhcp-client set [find comment=\"FO-Starlink\"] add-default-route=no script=\$slScript\n\
      /ip dhcp-client set [find comment=\"FO-MTN\"] default-route-distance=\$FOMTNDistance\n\
    }\n"
/system script remove [find name="FO-Apply"]
/system script add name="FO-Apply" policy=read,write,policy,test dont-require-permissions=no source="# FO-Apply: applies everything in Starlink-Settings. Safe to run any time.\n\
    /system script run Starlink-Settings\n\
    :global FOStarlinkPort; :global FOMTNPort; :global FOLANSubnet; :global FOMonitorHost\n\
    :global FOProbeInterval; :global FOProbeCount; :global FOProbeSpacing; :global FOProbeTimeout\n\
    :global FOProbeLoss; :global FOProbeMaxAvg; :global FOHoldSec; :global FOShieldMode; :global FOFlapWindow\n\
    :global FOWGIf; :global FOMSS; :global FOHotspot; :global FODNS\n\
    :global FOState; :global FOUpTicks; :global FOFlaps\n\
    \n\
    # 1. Ports and DHCP clients\n\
    /system script run FO-Ports\n\
    \n\
    # 2. Starlink gateway: from DHCP, else the existing route, else the Starlink default\n\
    #    (waits up to 5s for a fresh DHCP lease after a port change)\n\
    :local n 0\n\
    :do {\n\
      :while (\$n < 10 && [/ip dhcp-client get [:pick [/ip dhcp-client find comment=\"FO-Starlink\"] 0] status] != \"bound\") do={ :delay 500ms; :set n (\$n + 1) }\n\
    } on-error={}\n\
    :local gw \"\"\n\
    :do { :set gw [:tostr [/ip dhcp-client get [:pick [/ip dhcp-client find comment=\"FO-Starlink\"] 0] gateway]] } on-error={}\n\
    :if (\$gw = \"\") do={ :do { :set gw [:tostr [/ip route get [:pick [/ip route find comment=\"FO-Starlink-Main\"] 0] gateway]] } on-error={} }\n\
    :if (\$gw = \"\") do={ :set gw \"192.168.1.1\" }\n\
    \n\
    # 3. Routes. The monitor host can only ever be reached through Starlink.\n\
    :if ([:len [/ip route find comment=\"FO-Starlink-Main\"]] = 0) do={\n\
      /ip route add dst-address=0.0.0.0/0 gateway=\$gw distance=1 comment=\"FO-Starlink-Main\"\n\
    }\n\
    /ip route remove [find comment=\"FO-Starlink-Monitor\"]\n\
    /ip route remove [find comment=\"FO-Monitor-Blackhole\"]\n\
    /ip route add dst-address=(\$FOMonitorHost . \"/32\") gateway=\$gw distance=1 comment=\"FO-Starlink-Monitor\"\n\
    /ip route add dst-address=(\$FOMonitorHost . \"/32\") blackhole distance=10 comment=\"FO-Monitor-Blackhole\"\n\
    \n\
    # 4. Sensor. Netwatch pulls the Starlink route itself the moment a burst fails.\n\
    /tool netwatch remove [find comment=\"FO-Probe\"]\n\
    :local down (\":if ([/interface get [find name=\\\"\" . \$FOMTNPort . \"\\\"] running]) do={ /ip route disable [find comment=\\\"FO-Starlink-Main\\\"] }\")\n\
    /tool netwatch add host=\$FOMonitorHost type=icmp interval=\$FOProbeInterval timeout=\$FOProbeTimeout packet-count=\$FOProbeCount packet-interval=\$FOProbeSpacing thr-loss-percent=\$FOProbeLoss thr-avg=\$FOProbeMaxAvg early-failure-detection=yes startup-delay=30s up-script=\"\" down-script=\$down comment=\"FO-Probe\"\n\
    \n\
    # 5. VPN plumbing\n\
    :local wg \$FOWGIf\n\
    :if ([:len [/interface wireguard find name=\$wg]] = 0) do={ /interface wireguard add name=\$wg mtu=1280 comment=\"FO-WG\" }\n\
    :if ([:len [/routing table find name=\"VPN\"]] = 0) do={ /routing table add name=VPN fib }\n\
    /ip route remove [find comment=\"FO-VPN-Default\"]\n\
    /ip route add dst-address=0.0.0.0/0 gateway=\$wg routing-table=VPN comment=\"FO-VPN-Default\"\n\
    /ip firewall nat remove [find comment=\"FO-VPN-NAT\"]\n\
    /ip firewall nat add chain=srcnat out-interface=\$wg action=masquerade comment=\"FO-VPN-NAT\"\n\
    \n\
    # Local networks that never go into the VPN (add your own to list FO-Local)\n\
    /ip firewall address-list remove [find list=\"FO-Local\" comment=\"FO-Setting\"]\n\
    /ip firewall address-list add list=\"FO-Local\" address=\$FOLANSubnet comment=\"FO-Setting\"\n\
    \n\
    # MSS clamp only for tunnel traffic, so direct traffic keeps full speed\n\
    /ip firewall mangle remove [find comment=\"FO-MSS\"]\n\
    :local mssRange ((\$FOMSS + 1) . \"-65535\")\n\
    /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn out-interface=\$wg tcp-mss=\$mssRange action=change-mss new-mss=\$FOMSS passthrough=yes comment=\"FO-MSS\"\n\
    /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn in-interface=\$wg tcp-mss=\$mssRange action=change-mss new-mss=\$FOMSS passthrough=yes comment=\"FO-MSS\"\n\
    \n\
    # Shield rule (rebuilt, keeps its current on/off state)\n\
    :local on false\n\
    :foreach r in=[/ip firewall mangle find comment=\"FO-VPN-Shield\"] do={\n\
      :if ([/ip firewall mangle get \$r disabled] = false) do={ :set on true }\n\
    }\n\
    /ip firewall mangle remove [find comment=\"FO-VPN-Shield\"]\n\
    :local hs false\n\
    :if (\$FOHotspot = \"yes\") do={ :set hs true }\n\
    :if (\$FOHotspot = \"auto\" && [:len [/ip hotspot find]] > 0) do={ :set hs true }\n\
    :if (\$hs) do={\n\
      /ip firewall mangle add chain=prerouting src-address-list=FO-Local dst-address-list=!FO-Local hotspot=auth action=mark-routing new-routing-mark=VPN passthrough=yes disabled=yes comment=\"FO-VPN-Shield\"\n\
    } else={\n\
      /ip firewall mangle add chain=prerouting src-address-list=FO-Local dst-address-list=!FO-Local action=mark-routing new-routing-mark=VPN passthrough=yes disabled=yes comment=\"FO-VPN-Shield\"\n\
    }\n\
    :local wgOn ([/interface wireguard get [:pick [/interface wireguard find name=\$wg] 0] disabled] = false)\n\
    :if (\$FOShieldMode = \"always\") do={ :set on true }\n\
    :if (\$FOShieldMode = \"off\" || \$wgOn = false) do={ :set on false }\n\
    :if (\$on) do={ /ip firewall mangle enable [find comment=\"FO-VPN-Shield\"] }\n\
    \n\
    # FastTrack skips mangle rules, so it stays off\n\
    /ip firewall filter disable [find action=\"fasttrack-connection\"]\n\
    \n\
    # 6. DNS\n\
    /ip dns set servers=\$FODNS allow-remote-requests=yes\n\
    \n\
    # 7. Schedulers (added once, then only the cooldown interval is updated)\n\
    :if ([:len [/system scheduler find name=\"FO-Boot\"]] = 0) do={\n\
      /system scheduler add name=\"FO-Boot\" start-time=startup interval=0 on-event=\"FO-Boot\" policy=read,write,policy,test\n\
    }\n\
    :if ([:len [/system scheduler find name=\"FO-Brain\"]] = 0) do={\n\
      /system scheduler add name=\"FO-Brain\" start-date=[/system clock get date] start-time=[/system clock get time] interval=1s on-event=\"FO-Brain\" policy=read,write,policy,test\n\
    }\n\
    :if ([:len [/system scheduler find name=\"FO-Cooldown\"]] = 0) do={\n\
      /system scheduler add name=\"FO-Cooldown\" start-date=[/system clock get date] start-time=[/system clock get time] interval=\$FOFlapWindow on-event=\"FO-Cooldown\" policy=read,write,policy,test\n\
    } else={\n\
      /system scheduler set [find name=\"FO-Cooldown\"] interval=\$FOFlapWindow\n\
    }\n\
    \n\
    # 8. Fresh runtime state\n\
    :set FOState \"up\"\n\
    :set FOUpTicks 0\n\
    :if ([:typeof \$FOFlaps] = \"nothing\") do={ :set FOFlaps 0 }\n\
    /ip route enable [find comment=\"FO-Starlink-Main\"]\n\
    :log warning (\"FO-Apply: done. Starlink=\" . \$FOStarlinkPort . \" MTN=\" . \$FOMTNPort . \" hold=\" . \$FOHoldSec . \"s shield=\" . \$FOShieldMode)\n"
/system script remove [find name="FO-Brain"]
/system script add name="FO-Brain" policy=read,write,policy,test dont-require-permissions=no source=":global FOMTNPort; :global FOHoldSec; :global FOShieldMode; :global FOFlapLimit; :global FOWGIf\n\
    :global FOState; :global FOUpTicks; :global FOFlaps\n\
    :if ([:typeof \$FOHoldSec] = \"nothing\") do={ /system script run Starlink-Settings }\n\
    :if ([:typeof \$FOState] = \"nothing\") do={ :set FOState \"up\"; :set FOUpTicks 0; :set FOFlaps 0 }\n\
    :local nw [/tool netwatch get [find comment=\"FO-Probe\"] status]\n\
    :local rt [:pick [/ip route find comment=\"FO-Starlink-Main\"] 0]\n\
    :local rtOff [/ip route get \$rt disabled]\n\
    :local mtn [/interface get [find name=\$FOMTNPort] running]\n\
    :if (\$rtOff && !\$mtn) do={\n\
      /ip route enable \$rt\n\
      :set rtOff false\n\
      :log warning \"FO: MTN link down, Starlink route restored\"\n\
    }\n\
    :if (\$nw = \"down\") do={\n\
      :set FOUpTicks 0\n\
      :if (\$mtn && !\$rtOff) do={ /ip route disable \$rt; :set rtOff true }\n\
    }\n\
    :if (\$FOState = \"up\" && (\$nw = \"down\" || \$rtOff)) do={\n\
      :set FOState \"down\"\n\
      :set FOFlaps (\$FOFlaps + 1)\n\
      :local via \"MTN\"\n\
      :if (!\$mtn) do={ :set via \"nothing (MTN link down)\" }\n\
      :log warning (\"FO: Starlink lost, now on \" . \$via . \". Drops this window: \" . \$FOFlaps)\n\
      :if (\$FOShieldMode = \"auto\" && \$FOFlaps >= \$FOFlapLimit) do={\n\
        :if ([/interface wireguard get [find name=\$FOWGIf] disabled]) do={\n\
          :log warning \"FO: VPN shield skipped (VPN paused)\"\n\
        } else={\n\
          /ip firewall mangle enable [find comment=\"FO-VPN-Shield\"]\n\
          :log warning \"FO: VPN shield ON\"\n\
        }\n\
      }\n\
    }\n\
    :if (\$FOState = \"down\" && \$nw = \"up\") do={\n\
      :set FOUpTicks (\$FOUpTicks + 1)\n\
      :if (\$FOUpTicks >= \$FOHoldSec) do={\n\
        /ip route enable \$rt\n\
        :set FOState \"up\"\n\
        :set FOUpTicks 0\n\
        :log warning \"FO: Starlink stable, back on Starlink\"\n\
      }\n\
    }\n"
/system script remove [find name="FO-Cooldown"]
/system script add name="FO-Cooldown" policy=read,write,policy,test dont-require-permissions=no source=":global FOFlaps; :global FOFlapLimit; :global FOShieldMode\n\
    :if (\$FOShieldMode = \"auto\" && [:tonum \$FOFlaps] < [:tonum \$FOFlapLimit]) do={\n\
      :if ([:len [/ip firewall mangle find comment=\"FO-VPN-Shield\" disabled=no]] > 0) do={\n\
        /ip firewall mangle disable [find comment=\"FO-VPN-Shield\"]\n\
        :log warning \"FO: quiet window, VPN shield OFF\"\n\
      }\n\
    }\n\
    :set FOFlaps 0\n"
/system script remove [find name="FO-Boot"]
/system script add name="FO-Boot" policy=read,write,policy,test dont-require-permissions=no source="/system script run Starlink-Settings\n\
    /system script run WG-Profiles\n\
    :global FOState \"up\"\n\
    :global FOUpTicks 0\n\
    :global FOFlaps 0\n\
    /ip route enable [find comment=\"FO-Starlink-Main\"]\n\
    :log info \"FO: boot init done\"\n"
/system script remove [find name="FO-VPN-Toggle"]
/system script add name="FO-VPN-Toggle" policy=read,write,policy,test dont-require-permissions=no source="# FO-VPN-Toggle: pause or resume the VPN.\n\
    # While paused, the auto shield will not switch it back on (survives reboot).\n\
    :global FOWGIf; :global FOShieldMode\n\
    :if ([:typeof \$FOWGIf] = \"nothing\") do={ /system script run Starlink-Settings }\n\
    :local i [:pick [/interface wireguard find name=\$FOWGIf] 0]\n\
    :if ([/interface wireguard get \$i disabled]) do={\n\
      /interface wireguard enable \$i\n\
      :if (\$FOShieldMode != \"off\") do={ /ip firewall mangle enable [find comment=\"FO-VPN-Shield\"] }\n\
      :log warning \"FO: VPN resumed (shield on, auto mode active)\"\n\
    } else={\n\
      /interface wireguard disable \$i\n\
      /ip firewall mangle disable [find comment=\"FO-VPN-Shield\"]\n\
      :log warning \"FO: VPN paused (auto shield suspended)\"\n\
    }\n"
/system script remove [find name="FO-Status"]
/system script add name="FO-Status" policy=read,write,policy,test dont-require-permissions=no source="# FO-Status: one-screen summary. Prints in Terminal and writes to the Log\n\
    # (so it also works from WebFig \"Run Script\").\n\
    :global FOStarlinkPort; :global FOMTNPort; :global FOShieldMode; :global FOWGIf; :global FOHoldSec\n\
    :global FOFlaps; :global WGActive; :global WGProfiles\n\
    :if ([:typeof \$FOWGIf] = \"nothing\") do={ /system script run Starlink-Settings }\n\
    :if ([:typeof \$WGActive] = \"nothing\") do={ /system script run WG-Profiles }\n\
    :local out do={ :put \$1; :log info (\"FO-Status: \" . \$1) }\n\
    \n\
    :local nw [/tool netwatch get [find comment=\"FO-Probe\"] status]\n\
    :local wan \"Starlink\"\n\
    :if ([/ip route get [find comment=\"FO-Starlink-Main\"] disabled]) do={ :set wan \"MTN (backup)\" }\n\
    :local sh \"OFF\"\n\
    :if ([:len [/ip firewall mangle find comment=\"FO-VPN-Shield\" disabled=no]] > 0) do={ :set sh \"ON\" }\n\
    :local hsk \"never\"\n\
    :foreach p in=[/interface wireguard peers find interface=\$FOWGIf] do={\n\
      :local h [/interface wireguard peers get \$p last-handshake]\n\
      :if ([:typeof \$h] != \"nil\" && [:typeof \$h] != \"nothing\") do={ :set hsk ([:tostr \$h] . \" ago\") }\n\
    }\n\
    :local names \"\"\n\
    :foreach k,v in=\$WGProfiles do={ :set names (\$names . \$k . \" \") }\n\
    \n\
    \$out (\"Internet via    : \" . \$wan)\n\
    \$out (\"Starlink probe  : \" . \$nw . \" on \" . \$FOStarlinkPort)\n\
    \$out (\"MTN link        : \" . [/interface get [find name=\$FOMTNPort] running] . \" on \" . \$FOMTNPort)\n\
    \$out (\"Switch-back     : after \" . \$FOHoldSec . \"s healthy\")\n\
    \$out (\"VPN shield      : \" . \$sh . \" (mode \" . \$FOShieldMode . \")\")\n\
    \$out (\"VPN paused      : \" . [/interface wireguard get [find name=\$FOWGIf] disabled])\n\
    \$out (\"VPN profile     : \" . \$WGActive . \", last handshake \" . \$hsk)\n\
    \$out (\"Profiles        : \" . \$names)\n\
    \$out (\"Drops in window : \" . \$FOFlaps)\n"
/system script remove [find name="WG-Apply"]
/system script add name="WG-Apply" policy=read,write,policy,test,sensitive dont-require-permissions=no source="# WG-Apply: loads a profile from WG-Profiles onto the VPN interface.\n\
    #   Use the WGActive profile:   /system script run WG-Apply\n\
    #   Switch to another one:      :global WGPick \"proton-nl\"; /system script run WG-Apply\n\
    # A pick is saved back into WG-Profiles, so it survives reboots.\n\
    /system script run WG-Profiles\n\
    :global WGProfiles; :global WGActive; :global WGPick; :global FOWGIf\n\
    :if ([:typeof \$FOWGIf] = \"nothing\") do={ /system script run Starlink-Settings }\n\
    \n\
    :local name \$WGActive\n\
    :if ([:typeof \$WGPick] = \"str\") do={ :if (\$WGPick != \"\") do={ :set name \$WGPick } }\n\
    :set WGPick \"\"\n\
    :local p (\$WGProfiles->\$name)\n\
    :if ([:typeof \$p] != \"array\") do={ :error (\"WG-Apply: no profile called '\" . \$name . \"'\") }\n\
    :local mtu (\$p->\"mtu\")\n\
    :if ([:typeof \$mtu] = \"nothing\") do={ :set mtu 1280 }\n\
    :local psk (\$p->\"psk\")\n\
    :if ([:typeof \$psk] = \"nothing\") do={ :set psk \"\" }\n\
    \n\
    :local wg \$FOWGIf\n\
    :if ([:len [/interface wireguard find name=\$wg]] = 0) do={ /interface wireguard add name=\$wg }\n\
    /interface wireguard set [find name=\$wg] private-key=(\$p->\"priv\") mtu=\$mtu\n\
    /interface wireguard peers remove [find interface=\$wg]\n\
    /interface wireguard peers add interface=\$wg public-key=(\$p->\"pub\") endpoint-address=(\$p->\"host\") endpoint-port=(\$p->\"port\") allowed-address=0.0.0.0/0 persistent-keepalive=25s comment=(\"FO-WG \" . \$name)\n\
    :if (\$psk != \"\") do={ /interface wireguard peers set [find interface=\$wg] preshared-key=\$psk }\n\
    \n\
    # Exactly one address on the tunnel (stale /32s break return traffic)\n\
    /ip address remove [find interface=\$wg]\n\
    /ip address add address=(\$p->\"addr\") interface=\$wg comment=(\"FO-WG \" . \$name)\n\
    \n\
    # Save the choice into WG-Profiles\n\
    :if (\$name != \$WGActive) do={\n\
      :local key \":global WGActive \\\"\"\n\
      :local src [/system script get [find name=\"WG-Profiles\"] source]\n\
      :local a [:find \$src \$key]\n\
      :if ([:typeof \$a] = \"num\") do={\n\
        :local s (\$a + [:len \$key])\n\
        :local e (\$s + [:len \$WGActive])\n\
        :if ([:pick \$src \$s \$e] = \$WGActive) do={\n\
          /system script set [find name=\"WG-Profiles\"] source=([:pick \$src 0 \$s] . \$name . [:pick \$src \$e [:len \$src]])\n\
        }\n\
      }\n\
      :set WGActive \$name\n\
    }\n\
    :log warning (\"WG-Apply: VPN now uses profile \" . \$name)\n"
/system script remove [find name="WG-Import"]
/system script add name="WG-Import" policy=read,write,policy,test,sensitive dont-require-permissions=no source="# WG-Import: saves the WireGuard config that is live on the router as a\n\
    # profile in WG-Profiles and makes it the active one. Other profiles are kept.\n\
    #   Save as \"current\":       /system script run WG-Import\n\
    #   Save under a name:       :global WGImportName \"mullvad-lon\"; /system script run WG-Import\n\
    :global FOWGIf; :global WGImportName; :global WGProfiles; :global WGActive\n\
    :if ([:len [/system script find name=\"Starlink-Settings\"]] > 0) do={ /system script run Starlink-Settings }\n\
    :local wg \$FOWGIf\n\
    :if ([:typeof \$wg] != \"str\" || \$wg = \"\") do={ :set wg \"wg-commercial\" }\n\
    :local name \"current\"\n\
    :if ([:typeof \$WGImportName] = \"str\") do={ :if (\$WGImportName != \"\") do={ :set name \$WGImportName } }\n\
    :set WGImportName \"\"\n\
    :if ([:typeof [:find \$name \"\\\"\"]] = \"num\" || [:typeof [:find \$name \"\\\\\"]] = \"num\") do={ :error \"WG-Import: the profile name cannot contain quotes or backslashes\" }\n\
    \n\
    # 1. Read the live config\n\
    :local i [:pick [/interface wireguard find name=\$wg] 0]\n\
    :if ([:typeof \$i] = \"nil\") do={ :error (\"WG-Import: there is no WireGuard interface called \" . \$wg) }\n\
    :local peers [/interface wireguard peers find interface=\$wg]\n\
    :if ([:len \$peers] = 0) do={ :error (\"WG-Import: \" . \$wg . \" has no peer to import\") }\n\
    :if ([:len \$peers] > 1) do={ :log warning (\"WG-Import: \" . \$wg . \" has \" . [:len \$peers] . \" peers, importing the first one\") }\n\
    :local pr [:pick \$peers 0]\n\
    :local ads [/ip address find interface=\$wg]\n\
    :if ([:len \$ads] = 0) do={ :error (\"WG-Import: \" . \$wg . \" has no IPv4 address to import\") }\n\
    # Newest address = the one added last (older ones are usually stale)\n\
    :local ad [:pick \$ads ([:len \$ads] - 1)]\n\
    :if ([:len \$ads] > 1) do={\n\
      :local all \"\"\n\
      :foreach a in=\$ads do={ :set all (\$all . [/ip address get \$a address] . \" \") }\n\
      :log warning (\"WG-Import: several tunnel addresses (\" . \$all . \"), using \" . [/ip address get \$ad address] . \". Check it, then run WG-Apply to remove the others\")\n\
    }\n\
    :local psk [/interface wireguard peers get \$pr preshared-key]\n\
    :if ([:typeof \$psk] != \"str\") do={ :set psk \"\" }\n\
    :local prof [:toarray \"\"]\n\
    :set (\$prof->\"priv\") [/interface wireguard get \$i private-key]\n\
    :set (\$prof->\"pub\") [/interface wireguard peers get \$pr public-key]\n\
    :set (\$prof->\"psk\") \$psk\n\
    :set (\$prof->\"addr\") [:tostr [/ip address get \$ad address]]\n\
    :set (\$prof->\"host\") [:tostr [/interface wireguard peers get \$pr endpoint-address]]\n\
    :set (\$prof->\"port\") [/interface wireguard peers get \$pr endpoint-port]\n\
    :set (\$prof->\"mtu\") [/interface wireguard get \$i mtu]\n\
    \n\
    # 2. Merge with the existing profiles\n\
    :local old \"\"\n\
    :if ([:len [/system script find name=\"WG-Profiles\"]] > 0) do={\n\
      :set old [/system script get [find name=\"WG-Profiles\"] source]\n\
      /system script run WG-Profiles\n\
    }\n\
    :if ([:typeof \$WGProfiles] != \"array\") do={ :set WGProfiles [:toarray \"\"] }\n\
    :set (\$WGProfiles->\$name) \$prof\n\
    \n\
    # 3. Rewrite WG-Profiles (one line per profile)\n\
    :local body \"\"\n\
    :foreach k,v in=\$WGProfiles do={\n\
      :local mtu (\$v->\"mtu\")\n\
      :if ([:typeof \$mtu] = \"nothing\") do={ :set mtu 1280 }\n\
      :local pk (\$v->\"psk\")\n\
      :if ([:typeof \$pk] = \"nothing\") do={ :set pk \"\" }\n\
      :set body (\$body . \":set (\\\$WGProfiles->\\\"\" . \$k . \"\\\") {\\\"priv\\\"=\\\"\" . (\$v->\"priv\") . \"\\\";\\\"pub\\\"=\\\"\" . (\$v->\"pub\") . \"\\\";\\\"psk\\\"=\\\"\" . \$pk . \"\\\";\\\"addr\\\"=\\\"\" . (\$v->\"addr\") . \"\\\";\\\"host\\\"=\\\"\" . (\$v->\"host\") . \"\\\";\\\"port\\\"=\" . (\$v->\"port\") . \";\\\"mtu\\\"=\" . \$mtu . \"}\\n\")\n\
    }\n\
    :local head \"# ================================================================\\n#  WIREGUARD PROFILES (FO v2)\\n#  One :set line per VPN server. Copy the example line, remove the #,\\n#  give it a name and paste the values from your provider's .conf:\\n#    priv = [Interface] PrivateKey     addr = [Interface] Address (IPv4 only)\\n#    pub  = [Peer] PublicKey           host = Endpoint IP (before the :)\\n#    psk  = [Peer] PresharedKey or \\\"\\\"  port = Endpoint port (after the :)\\n#    mtu  = 1280\\n#  Switch server:  :global WGPick \\\"name\\\"; /system script run WG-Apply\\n# ================================================================\\n:global WGProfiles [:toarray \\\"\\\"]\\n\"\n\
    :local ex \"#:set (\\\$WGProfiles->\\\"example\\\") {\\\"priv\\\"=\\\"PRIVATE_KEY\\\";\\\"pub\\\"=\\\"SERVER_PUBLIC_KEY\\\";\\\"psk\\\"=\\\"\\\";\\\"addr\\\"=\\\"10.2.0.2/32\\\";\\\"host\\\"=\\\"203.0.113.10\\\";\\\"port\\\"=51820;\\\"mtu\\\"=1280}\\n\"\n\
    :local tail \"\\n# Profile WG-Apply uses when no pick is given\\n:global WGActive \\\"\"\n\
    :local src (\$head . \$body . \$ex . \$tail . \$name . \"\\\"\\n\")\n\
    :if (\$old != \"\") do={\n\
      /system script remove [find name=\"WG-Profiles-backup\"]\n\
      /system script add name=\"WG-Profiles-backup\" policy=read source=(\"# Copy of WG-Profiles before WG-Import. Not used by anything; delete when happy.\\n\" . \$old)\n\
      /system script set [find name=\"WG-Profiles\"] source=\$src\n\
    } else={\n\
      /system script add name=\"WG-Profiles\" policy=read,write,policy,test source=\$src\n\
    }\n\
    :set WGActive \$name\n\
    :log warning (\"WG-Import: saved \" . \$wg . \" as profile '\" . \$name . \"' (endpoint \" . (\$prof->\"host\") . \":\" . (\$prof->\"port\") . \", address \" . (\$prof->\"addr\") . \")\")\n\
    :put (\"Saved \" . \$wg . \" as WireGuard profile '\" . \$name . \"'. Address \" . (\$prof->\"addr\") . \", endpoint \" . (\$prof->\"host\") . \":\" . (\$prof->\"port\"))\n"

# 3. Settings: kept if already v2, otherwise the old one is renamed Starlink-Settings-old
{
:local keep false
:foreach s in=[/system script find name="Starlink-Settings"] do={
  :if ([:typeof [:find [/system script get $s source] "FOStarlinkPort"]] = "num") do={ :set keep true } else={
    /system script remove [find name="Starlink-Settings-old"]
    /system script set $s name="Starlink-Settings-old"
    :log warning "FO v2: old Starlink-Settings renamed to Starlink-Settings-old" } }
:if (!$keep) do={
  /system script add name="Starlink-Settings" policy=read,write,policy,test source="# ================================================================\n\
    #  STARLINK / MTN FAILOVER SETTINGS  (FO v2)\n\
    #  1. Change the values below.  2. Run the FO-Apply script.\n\
    #  Keep the quotes where they are. Lines starting with # are notes.\n\
    # ================================================================\n\
    \n\
    # ---- Ports -------------------------------------------------------\n\
    # Port the Starlink Mini is plugged into\n\
    :global FOStarlinkPort \"ether1\"\n\
    # Port the MTN 4G router is plugged into\n\
    :global FOMTNPort \"ether2\"\n\
    # LAN bridge (a port that stops being WAN is put back here)\n\
    :global FOLANBridge \"bridge\"\n\
    # LAN subnet (never sent into the VPN)\n\
    :global FOLANSubnet \"192.168.88.0/24\"\n\
    \n\
    # ---- Starlink sensor (ping stream through Starlink only) ---------\n\
    # Do NOT use this host as a DNS server\n\
    :global FOMonitorHost \"9.9.9.9\"\n\
    # A new burst of pings starts this often\n\
    :global FOProbeInterval \"1s\"\n\
    # Pings per burst, and the gap between them\n\
    :global FOProbeCount 5\n\
    :global FOProbeSpacing \"100ms\"\n\
    # How long to wait for each reply\n\
    :global FOProbeTimeout \"500ms\"\n\
    # Starlink counts as DOWN when loss in a burst passes this percent...\n\
    :global FOProbeLoss 50\n\
    # ...or when the average ping goes above this\n\
    :global FOProbeMaxAvg \"300ms\"\n\
    \n\
    # ---- Switching ---------------------------------------------------\n\
    # Seconds Starlink must stay healthy before traffic moves back\n\
    :global FOHoldSec 2\n\
    # Route distance of the MTN backup route (must be above 1)\n\
    :global FOMTNDistance 2\n\
    \n\
    # ---- VPN shield --------------------------------------------------\n\
    # \"auto\"   = turn on after FOFlapLimit drops within FOFlapWindow\n\
    # \"always\" = keep LAN traffic in the VPN all the time\n\
    # \"off\"    = never put LAN traffic in the VPN\n\
    :global FOShieldMode \"auto\"\n\
    :global FOFlapLimit 2\n\
    :global FOFlapWindow \"10m\"\n\
    # WireGuard interface used by the shield\n\
    :global FOWGIf \"wg-commercial\"\n\
    # TCP MSS inside the tunnel (MTU 1280 -> 1240)\n\
    :global FOMSS 1240\n\
    # Captive portal support: \"auto\" (detect Hotspot), \"yes\" or \"no\"\n\
    :global FOHotspot \"auto\"\n\
    \n\
    # ---- DNS ---------------------------------------------------------\n\
    :global FODNS \"8.8.8.8,1.1.1.1\"\n"
} }

# 4. WireGuard profiles: kept if present, otherwise created with your
#    current VPN imported as profile "current"
{
:if ([:len [/system script find name="WG-Profiles"]] = 0) do={
  /system script run Starlink-Settings
  :global FOWGIf
  :local cur ""
  :local act ""
  :do {
    :local i [:pick [/interface wireguard find name=$FOWGIf] 0]
    :local pr [:pick [/interface wireguard peers find interface=$FOWGIf] 0]
    :local ad [:pick [/ip address find interface=$FOWGIf] 0]
    :local psk [:tostr [/interface wireguard peers get $pr preshared-key]]
    :set cur (":set (\$WGProfiles->\"current\") {\"priv\"=\"" . [/interface wireguard get $i private-key] . "\";\"pub\"=\"" . [/interface wireguard peers get $pr public-key] . "\";\"psk\"=\"" . $psk . "\";\"addr\"=\"" . [/ip address get $ad address] . "\";\"host\"=\"" . [/interface wireguard peers get $pr endpoint-address] . "\";\"port\"=" . [/interface wireguard peers get $pr endpoint-port] . ";\"mtu\"=" . [/interface wireguard get $i mtu] . "}\n")
    :set act "current"
  } on-error={ :set cur ""; :set act ""; :log warning "FO v2: no existing VPN found to import" }
  :local head "# ================================================================\n\
    #  WIREGUARD PROFILES (FO v2)\n\
    #  One :set line per VPN server. Copy the example line, remove the #,\n\
    #  give it a name and paste the values from your provider's .conf:\n\
    #    priv = [Interface] PrivateKey     addr = [Interface] Address (IPv4 only)\n\
    #    pub  = [Peer] PublicKey           host = Endpoint IP (before the :)\n\
    #    psk  = [Peer] PresharedKey or \"\"  port = Endpoint port (after the :)\n\
    #    mtu  = 1280\n\
    #  Switch server:  :global WGPick \"name\"; /system script run WG-Apply\n\
    # ================================================================\n\
    :global WGProfiles [:toarray \"\"]\n"
  :local ex "#:set (\$WGProfiles->\"example\") {\"priv\"=\"PRIVATE_KEY\";\"pub\"=\"SERVER_PUBLIC_KEY\";\"psk\"=\"\";\"addr\"=\"10.2.0.2/32\";\"host\"=\"203.0.113.10\";\"port\"=51820;\"mtu\"=1280}\n"
  :local tail "\n\
    # Profile WG-Apply uses when no pick is given\n\
    :global WGActive \""
  /system script add name="WG-Profiles" policy=read,write,policy,test source=($head . $cur . $ex . $tail . $act . "\"\n")
} }

# 5. Apply everything and initialise
/system script run FO-Apply
/system script run FO-Boot
:log warning "FO v2: install finished"
:put "FO v2 installed. Run /system script run FO-Status to check."
