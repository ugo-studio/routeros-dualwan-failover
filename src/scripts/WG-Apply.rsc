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
