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
