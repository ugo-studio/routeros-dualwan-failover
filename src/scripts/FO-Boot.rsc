# FO-Boot: runs once at startup. Loads settings and starts on Starlink.
/system script run Starlink-Settings
/system script run WG-Profiles
:global FOState "up"
:global FOUpTicks 0
:global FOFlaps 0
/ip route enable [find comment="FO-Starlink-Main"]
:log info "FO: boot init done"
