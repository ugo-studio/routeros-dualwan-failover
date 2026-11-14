# ================================================================
#  FO WG IMPORT: saves the WireGuard config that is live on the router
#  as a profile in WG-Profiles (other profiles are kept) and installs
#  the WG-Import script for later use. Works before or after v2 install.
#  Import:  /import file-name=fo-wg-import.rsc
#  Saves the profile as "current". For another name, after this import run:
#    :global WGImportName "mullvad-lon"; /system script run WG-Import
# ================================================================
/system script remove [find name="WG-Import"]
/system script add name="WG-Import" policy=read,write,policy,test,sensitive dont-require-permissions=no source="# WG-Import: saves the WireGuard config that is live on the router as a\n\
    # profile in WG-Profiles and makes it the active one. Other profiles are kept.\n\
    #   Save as \"current\":       /system script run WG-Import\n\
    #   Save under a name:       :global WGImportName \"mullvad-lon\"; /system script run WG-Import\n\
    :global FOWGIf; :global WGImportName; :global WGProfiles; :global WGActive\n\
    :if ([:len [/system script find name=\"Starlink-Settings\"]] > 0) do={ /system script run Starlink-Settings }\n\
    :local wg \$FOWGIf\n\
    :if ([:typeof \$wg] != \"str\" || \$wg = \"\") do={ :set wg \"wg-commercial\" }\n\
    :local name \"current\"\n\
    :if ([:typeof \$WGImportName] = \"str\") do={ :if (\$WGImportName != \"\") do={ :set name \$WGImportName } }\n\
    :set WGImportName \"\"\n\
    :if ([:typeof [:find \$name \"\\\"\"]] = \"num\" || [:typeof [:find \$name \"\\\\\"]] = \"num\") do={ :error \"WG-Import: the profile name cannot contain quotes or backslashes\" }\n\
    \n\
    # 1. Read the live config\n\
    :local i [:pick [/interface wireguard find name=\$wg] 0]\n\
    :if ([:typeof \$i] = \"nil\") do={ :error (\"WG-Import: there is no WireGuard interface called \" . \$wg) }\n\
    :local peers [/interface wireguard peers find interface=\$wg]\n\
    :if ([:len \$peers] = 0) do={ :error (\"WG-Import: \" . \$wg . \" has no peer to import\") }\n\
    :if ([:len \$peers] > 1) do={ :log warning (\"WG-Import: \" . \$wg . \" has \" . [:len \$peers] . \" peers, importing the first one\") }\n\
    :local pr [:pick \$peers 0]\n\
    :local ads [/ip address find interface=\$wg]\n\
    :if ([:len \$ads] = 0) do={ :error (\"WG-Import: \" . \$wg . \" has no IPv4 address to import\") }\n\
    # Newest address = the one added last (older ones are usually stale)\n\
    :local ad [:pick \$ads ([:len \$ads] - 1)]\n\
    :if ([:len \$ads] > 1) do={\n\
      :local all \"\"\n\
      :foreach a in=\$ads do={ :set all (\$all . [/ip address get \$a address] . \" \") }\n\
      :log warning (\"WG-Import: several tunnel addresses (\" . \$all . \"), using \" . [/ip address get \$ad address] . \". Check it, then run WG-Apply to remove the others\")\n\
    }\n\
    :local psk [/interface wireguard peers get \$pr preshared-key]\n\
    :if ([:typeof \$psk] != \"str\") do={ :set psk \"\" }\n\
    :local prof [:toarray \"\"]\n\
    :set (\$prof->\"priv\") [/interface wireguard get \$i private-key]\n\
    :set (\$prof->\"pub\") [/interface wireguard peers get \$pr public-key]\n\
    :set (\$prof->\"psk\") \$psk\n\
    :set (\$prof->\"addr\") [:tostr [/ip address get \$ad address]]\n\
    :set (\$prof->\"host\") [:tostr [/interface wireguard peers get \$pr endpoint-address]]\n\
    :set (\$prof->\"port\") [/interface wireguard peers get \$pr endpoint-port]\n\
    :set (\$prof->\"mtu\") [/interface wireguard get \$i mtu]\n\
    \n\
    # 2. Merge with the existing profiles\n\
    :local old \"\"\n\
    :if ([:len [/system script find name=\"WG-Profiles\"]] > 0) do={\n\
      :set old [/system script get [find name=\"WG-Profiles\"] source]\n\
      /system script run WG-Profiles\n\
    }\n\
    :if ([:typeof \$WGProfiles] != \"array\") do={ :set WGProfiles [:toarray \"\"] }\n\
    :set (\$WGProfiles->\$name) \$prof\n\
    \n\
    # 3. Rewrite WG-Profiles (one line per profile)\n\
    :local body \"\"\n\
    :foreach k,v in=\$WGProfiles do={\n\
      :local mtu (\$v->\"mtu\")\n\
      :if ([:typeof \$mtu] = \"nothing\") do={ :set mtu 1280 }\n\
      :local pk (\$v->\"psk\")\n\
      :if ([:typeof \$pk] = \"nothing\") do={ :set pk \"\" }\n\
      :set body (\$body . \":set (\\\$WGProfiles->\\\"\" . \$k . \"\\\") {\\\"priv\\\"=\\\"\" . (\$v->\"priv\") . \"\\\";\\\"pub\\\"=\\\"\" . (\$v->\"pub\") . \"\\\";\\\"psk\\\"=\\\"\" . \$pk . \"\\\";\\\"addr\\\"=\\\"\" . (\$v->\"addr\") . \"\\\";\\\"host\\\"=\\\"\" . (\$v->\"host\") . \"\\\";\\\"port\\\"=\" . (\$v->\"port\") . \";\\\"mtu\\\"=\" . \$mtu . \"}\\n\")\n\
    }\n\
    :local head \"# ================================================================\\n#  WIREGUARD PROFILES (FO v2)\\n#  One :set line per VPN server. Copy the example line, remove the #,\\n#  give it a name and paste the values from your provider's .conf:\\n#    priv = [Interface] PrivateKey     addr = [Interface] Address (IPv4 only)\\n#    pub  = [Peer] PublicKey           host = Endpoint IP (before the :)\\n#    psk  = [Peer] PresharedKey or \\\"\\\"  port = Endpoint port (after the :)\\n#    mtu  = 1280\\n#  Switch server:  :global WGPick \\\"name\\\"; /system script run WG-Apply\\n# ================================================================\\n:global WGProfiles [:toarray \\\"\\\"]\\n\"\n\
    :local ex \"#:set (\\\$WGProfiles->\\\"example\\\") {\\\"priv\\\"=\\\"PRIVATE_KEY\\\";\\\"pub\\\"=\\\"SERVER_PUBLIC_KEY\\\";\\\"psk\\\"=\\\"\\\";\\\"addr\\\"=\\\"10.2.0.2/32\\\";\\\"host\\\"=\\\"203.0.113.10\\\";\\\"port\\\"=51820;\\\"mtu\\\"=1280}\\n\"\n\
    :local tail \"\\n# Profile WG-Apply uses when no pick is given\\n:global WGActive \\\"\"\n\
    :local src (\$head . \$body . \$ex . \$tail . \$name . \"\\\"\\n\")\n\
    :if (\$old != \"\") do={\n\
      /system script remove [find name=\"WG-Profiles-backup\"]\n\
      /system script add name=\"WG-Profiles-backup\" policy=read source=(\"# Copy of WG-Profiles before WG-Import. Not used by anything; delete when happy.\\n\" . \$old)\n\
      /system script set [find name=\"WG-Profiles\"] source=\$src\n\
    } else={\n\
      /system script add name=\"WG-Profiles\" policy=read,write,policy,test source=\$src\n\
    }\n\
    :set WGActive \$name\n\
    :log warning (\"WG-Import: saved \" . \$wg . \" as profile '\" . \$name . \"' (endpoint \" . (\$prof->\"host\") . \":\" . (\$prof->\"port\") . \", address \" . (\$prof->\"addr\") . \")\")\n\
    :put (\"Saved \" . \$wg . \" as WireGuard profile '\" . \$name . \"'. Address \" . (\$prof->\"addr\") . \", endpoint \" . (\$prof->\"host\") . \":\" . (\$prof->\"port\"))\n"
/system script run WG-Import
