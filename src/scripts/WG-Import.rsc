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
:local head {{WG_HEAD}}
:local ex {{WG_EXAMPLE}}
:local tail {{WG_TAIL}}
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
