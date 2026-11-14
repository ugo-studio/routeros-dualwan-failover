# FO-Cooldown: runs every FOFlapWindow. Turns the auto shield off after a quiet window.
:global FOFlaps; :global FOFlapLimit; :global FOShieldMode
:if ($FOShieldMode = "auto" && [:tonum $FOFlaps] < [:tonum $FOFlapLimit]) do={
  :if ([:len [/ip firewall mangle find comment="FO-VPN-Shield" disabled=no]] > 0) do={
    /ip firewall mangle disable [find comment="FO-VPN-Shield"]
    :log warning "FO: quiet window, VPN shield OFF"
  }
}
:set FOFlaps 0
