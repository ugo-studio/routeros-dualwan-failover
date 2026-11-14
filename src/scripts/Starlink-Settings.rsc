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
