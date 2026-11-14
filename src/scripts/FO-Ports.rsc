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
