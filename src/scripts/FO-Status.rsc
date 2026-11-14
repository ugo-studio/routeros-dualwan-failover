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
