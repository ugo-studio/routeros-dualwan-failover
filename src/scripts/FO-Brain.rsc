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
