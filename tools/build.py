#!/usr/bin/env python3
"""Builds dist/*.rsc and docs/MANUAL.md from the readable sources in src/.

Usage:  python3 tools/build.py && python3 tools/build_html.py
"""
import pathlib, re

TOOLS = pathlib.Path(__file__).resolve().parent
REPO = TOOLS.parent
SRC = REPO / "src" / "scripts"
OUT = REPO / "dist"
DOCS = REPO / "docs"

# name, source file, policy, strip comments?
SCRIPTS = [
    ("FO-Ports",      "FO-Ports.rsc",      "read,write,policy,test", False),
    ("FO-Apply",      "FO-Apply.rsc",      "read,write,policy,test", False),
    ("FO-Brain",      "FO-Brain.rsc",      "read,write,policy,test", True),   # runs every 1s: keep it lean
    ("FO-Cooldown",   "FO-Cooldown.rsc",   "read,write,policy,test", True),
    ("FO-Boot",       "FO-Boot.rsc",       "read,write,policy,test", True),
    ("FO-VPN-Toggle", "FO-VPN-Toggle.rsc", "read,write,policy,test", False),
    ("FO-Status",     "FO-Status.rsc",     "read,write,policy,test", False),
    ("WG-Apply",      "WG-Apply.rsc",      "read,write,policy,test,sensitive", False),
    ("WG-Import",     "WG-Import.rsc",     "read,write,policy,test,sensitive", False),
]


def resolve(fname):
    """Source text with the shared WG-Profiles template strings filled in."""
    text = (SRC / fname).read_text()
    for key, val in (("WG_HEAD", WG_HEAD), ("WG_EXAMPLE", WG_EXAMPLE), ("WG_TAIL", WG_TAIL)):
        text = text.replace("{{%s}}" % key, '"' + esc(val) + '"')
    return text


def load(fname, strip):
    text = resolve(fname)
    # join "\"-continued lines so every command is on one line
    text = re.sub(r"[ \t]*\\\n[ \t]*", " ", text)
    lines = text.splitlines()
    if strip:
        lines = [l for l in lines if l.strip() and not l.strip().startswith("#")]
    return "\n".join(lines).rstrip() + "\n"


def esc(s):
    """Escape text into a RouterOS double-quoted string literal."""
    return (s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
             .replace("?", "\\?").replace("\t", "    ").replace("\n", "\\n"))


def literal(s):
    """RouterOS string literal, wrapped like /export does (backslash-newline)."""
    parts = s.split("\n")
    chunks = [esc(p + "\n") for p in parts[:-1]]
    if parts[-1]:
        chunks.append(esc(parts[-1]))
    return '"' + "\\\n    ".join(chunks) + '"'


WG_HEAD = """# ================================================================
#  WIREGUARD PROFILES (FO v2)
#  One :set line per VPN server. Copy the example line, remove the #,
#  give it a name and paste the values from your provider's .conf:
#    priv = [Interface] PrivateKey     addr = [Interface] Address (IPv4 only)
#    pub  = [Peer] PublicKey           host = Endpoint IP (before the :)
#    psk  = [Peer] PresharedKey or ""  port = Endpoint port (after the :)
#    mtu  = 1280
#  Switch server:  :global WGPick "name"; /system script run WG-Apply
# ================================================================
:global WGProfiles [:toarray ""]
"""
WG_EXAMPLE = ('#:set ($WGProfiles->"example") {"priv"="PRIVATE_KEY";"pub"="SERVER_PUBLIC_KEY";'
              '"psk"="";"addr"="10.2.0.2/32";"host"="203.0.113.10";"port"=51820;"mtu"=1280}\n')
WG_TAIL = "\n# Profile WG-Apply uses when no pick is given\n:global WGActive \""


def build():
    o = []
    w = o.append
    w("# ================================================================")
    w("#  FO v2 INSTALLER: Starlink/MTN failover + VPN shield (RouterOS 7.24+)")
    w("#  Run fo-cleanup-v1.rsc first if you used the v1 manual.")
    w("#  Import:  /import file-name=fo-install-v2.rsc")
    w("#  Safe to re-import: your Starlink-Settings and WG-Profiles are kept.")
    w("# ================================================================")
    w(':log warning "FO v2: install started"')
    w("")
    w("# 1. Lock the bridge MAC (one time) so the LAN MAC never changes with ports")
    w('{ :foreach b in=[/interface bridge find name="bridge"] do={')
    w('  :if ([/interface bridge get $b auto-mac]) do={ /interface bridge set $b auto-mac=no admin-mac=[/interface bridge get $b mac-address] } } }')
    w("")
    w("# 2. Program scripts (always replaced with this version)")
    for name, fname, pol, strip in SCRIPTS:
        w(f'/system script remove [find name="{name}"]')
        w(f'/system script add name="{name}" policy={pol} dont-require-permissions=no source={literal(load(fname, strip))}')
    w("")
    w("# 3. Settings: kept if already v2, otherwise the old one is renamed Starlink-Settings-old")
    w("{")
    w(":local keep false")
    w(':foreach s in=[/system script find name="Starlink-Settings"] do={')
    w('  :if ([:typeof [:find [/system script get $s source] "FOStarlinkPort"]] = "num") do={ :set keep true } else={')
    w('    /system script remove [find name="Starlink-Settings-old"]')
    w('    /system script set $s name="Starlink-Settings-old"')
    w('    :log warning "FO v2: old Starlink-Settings renamed to Starlink-Settings-old" } }')
    w(":if (!$keep) do={")
    w(f'  /system script add name="Starlink-Settings" policy=read,write,policy,test source={literal(load("Starlink-Settings.rsc", False))}')
    w("} }")
    w("")
    w("# 4. WireGuard profiles: kept if present, otherwise created with your")
    w('#    current VPN imported as profile "current"')
    w("{")
    w(':if ([:len [/system script find name="WG-Profiles"]] = 0) do={')
    w("  /system script run Starlink-Settings")
    w("  :global FOWGIf")
    w('  :local cur ""')
    w('  :local act ""')
    w("  :do {")
    w("    :local i [:pick [/interface wireguard find name=$FOWGIf] 0]")
    w("    :local pr [:pick [/interface wireguard peers find interface=$FOWGIf] 0]")
    w("    :local ad [:pick [/ip address find interface=$FOWGIf] 0]")
    w("    :local psk [:tostr [/interface wireguard peers get $pr preshared-key]]")
    w('    :set cur (":set (\\$WGProfiles->\\"current\\") {\\"priv\\"=\\"" . [/interface wireguard get $i private-key] . '
      '"\\";\\"pub\\"=\\"" . [/interface wireguard peers get $pr public-key] . '
      '"\\";\\"psk\\"=\\"" . $psk . '
      '"\\";\\"addr\\"=\\"" . [/ip address get $ad address] . '
      '"\\";\\"host\\"=\\"" . [/interface wireguard peers get $pr endpoint-address] . '
      '"\\";\\"port\\"=" . [/interface wireguard peers get $pr endpoint-port] . '
      '";\\"mtu\\"=" . [/interface wireguard get $i mtu] . "}\\n")')
    w('    :set act "current"')
    w('  } on-error={ :set cur ""; :set act ""; :log warning "FO v2: no existing VPN found to import" }')
    w(f"  :local head {literal(WG_HEAD)}")
    w(f"  :local ex {literal(WG_EXAMPLE)}")
    w(f"  :local tail {literal(WG_TAIL)}")
    w('  /system script add name="WG-Profiles" policy=read,write,policy,test source=($head . $cur . $ex . $tail . $act . "\\"\\n")')
    w("} }")
    w("")
    w("# 5. Apply everything and initialise")
    w("/system script run FO-Apply")
    w("/system script run FO-Boot")
    w(':log warning "FO v2: install finished"')
    w(':put "FO v2 installed. Run /system script run FO-Status to check."')
    return "\n".join(o) + "\n"


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    (OUT / "fo-install-v2.rsc").write_text(build())
    (OUT / "fo-cleanup-v1.rsc").write_text((REPO / "src" / "fo-cleanup-v1.rsc").read_text())
    wgi = [
        "# ================================================================",
        "#  FO WG IMPORT: saves the WireGuard config that is live on the router",
        "#  as a profile in WG-Profiles (other profiles are kept) and installs",
        "#  the WG-Import script for later use. Works before or after v2 install.",
        "#  Import:  /import file-name=fo-wg-import.rsc",
        "#  Saves the profile as \"current\". For another name, after this import run:",
        "#    :global WGImportName \"mullvad-lon\"; /system script run WG-Import",
        "# ================================================================",
        '/system script remove [find name="WG-Import"]',
        f'/system script add name="WG-Import" policy=read,write,policy,test,sensitive dont-require-permissions=no source={literal(load("WG-Import.rsc", False))}',
        "/system script run WG-Import",
    ]
    (OUT / "fo-wg-import.rsc").write_text("\n".join(wgi) + "\n")
    # manual
    pols = {"Starlink-Settings": "read,write,policy,test"}
    pols.update({n: p for n, _, p, _ in SCRIPTS})
    files = [("Starlink-Settings", "Starlink-Settings.rsc")] + [(n, f) for n, f, _, _ in SCRIPTS]
    app = []
    for i, (n, f) in enumerate(files, 1):
        app.append(f"### A.{i} {n}\n\nPolicies: `{pols[n].replace(',', ', ')}`\n\n```routeros\n{resolve(f).rstrip()}\n```\n")
    wg = (WG_HEAD + ':set ($WGProfiles->"current") {"priv"="PRIVATE_KEY";"pub"="SERVER_PUBLIC_KEY";"psk"="";"addr"="10.64.0.2/32";"host"="203.0.113.20";"port"=51820;"mtu"=1280}\n'
          + WG_EXAMPLE + WG_TAIL + 'current"')
    man = (TOOLS / "manual.template.md").read_text()
    man = man.replace("{{APPENDIX}}", "\n".join(app)).replace("{{WGTEMPLATE}}", wg)
    DOCS.mkdir(exist_ok=True)
    (DOCS / "MANUAL.md").write_text(man)
    print("built dist/*.rsc and docs/MANUAL.md")
