# ================================================================
#  FO CLEANUP: removes the v1 failover objects (manual v1 and the
#  "continuous ping" tweak). Keeps your WireGuard interface, peer and
#  address so your current VPN details can be imported as a profile.
#  Import:  /import file-name=fo-cleanup-v1.rsc
# ================================================================
:log warning "FO cleanup: removing v1 objects"

# 1. Old schedulers and scripts (stop them first so nothing fights the cleanup)
/system scheduler remove [find name="Starlink-Monitor"]
/system scheduler remove [find name="VPN-Cooldown"]
/system script remove [find name="ToggleVPN"]

# 2. Old Netwatch sensors on 9.9.9.9 (keeps the new FO-Probe)
:foreach n in=[/tool netwatch find host="9.9.9.9"] do={
  :if ([/tool netwatch get $n comment] != "FO-Probe") do={ /tool netwatch remove $n }
}

# 3. Old routes
/ip route remove [find comment="Starlink-Route-Main"]
/ip route remove [find comment="Starlink-Route-Monitor"]
/ip route remove [find comment="Starlink-Leak-Prevention"]
:foreach r in=[/ip route find routing-table="VPN"] do={
  :if ([/ip route get $r comment] != "FO-VPN-Default") do={ /ip route remove $r }
}

# 4. Old firewall rules (v1 rules had no FO- comment)
/ip firewall mangle remove [find comment="VPN-Mangle-Rule"]
:foreach m in=[/ip firewall mangle find action="change-mss" new-mss=1240] do={
  :if ([/ip firewall mangle get $m comment] != "FO-MSS") do={ /ip firewall mangle remove $m }
}
:foreach n in=[/ip firewall nat find action="masquerade" out-interface="wg-commercial"] do={
  :if ([/ip firewall nat get $n comment] != "FO-VPN-NAT") do={ /ip firewall nat remove $n }
}

# 5. Old MTN DHCP client (v2 re-creates it as FO-MTN)
/ip dhcp-client remove [find comment="MTN-Backup"]

# 6. Old global variables
:foreach v in={"FlapCount";"LastFlapResetTime";"LastStarlinkState";"StarlinkUpCounter";"VPNSuspended";"IsVPNActive";"StarlinkHoldSec"} do={
  /system script environment remove [find name=$v]
}

:log warning "FO cleanup: done. Now import fo-install-v2.rsc"
:put "FO cleanup done. Now run:  /import file-name=fo-install-v2.rsc"
