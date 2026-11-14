#!/usr/bin/env python3
"""Builds docs/manual.html (standalone page) from docs/MANUAL.md and dist/*.rsc."""
import html, pathlib, re
import markdown

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent
OUT = REPO / "dist"
md_text = (REPO / "docs" / "MANUAL.md").read_text()

# Drop the markdown title block; the page has its own header.
md_text = md_text.split("\n---\n", 1)[1]

md = markdown.Markdown(extensions=["tables", "fenced_code", "toc"], extension_configs={"toc": {"toc_depth": "2-3"}})
body = md.convert(md_text)
toc = md.toc_tokens

TOK = re.compile(r'(?P<str>"(?:[^"\\]|\\.)*")|(?P<var>\$"[^"]*"|\$[A-Za-z_][\w]*)|(?P<cmd>(?<![\w\]>])/[a-z][\w-]*)|(?P<kw>:[a-z]+\b)|(?P<prop>[\w.-]+(?==))')


def hl_line(line):
    if line.lstrip().startswith("#"):
        return f'<span class="c">{html.escape(line)}</span>'
    out, pos = [], 0
    for m in TOK.finditer(line):
        out.append(html.escape(line[pos:m.start()]))
        cls = {"str": "s", "var": "v", "cmd": "k", "kw": "k", "prop": "p"}[m.lastgroup]
        out.append(f'<span class="{cls}">{html.escape(m.group())}</span>')
        pos = m.end()
    out.append(html.escape(line[pos:]))
    return "".join(out)


def code_block(code, lang, label=None):
    if lang == "routeros":
        inner = "\n".join(hl_line(l) for l in code.split("\n"))
    else:
        inner = html.escape(code)
    tag = label or ("RouterOS" if lang == "routeros" else "Diagram")
    return (f'<div class="code"><div class="code-bar"><span>{tag}</span>'
            f'<button type="button" class="copy">Copy</button></div>'
            f'<pre><code>{inner}</code></pre></div>')


def repl_code(m):
    lang = m.group(1) or ""
    code = html.unescape(m.group(2)).rstrip("\n")
    return code_block(code, lang)


body = re.sub(r'<pre><code(?: class="language-([\w-]+)")?>(.*?)</code></pre>', repl_code, body, flags=re.S)
body = body.replace("<hr />", "")
body = re.sub(r"<table>", '<div class="table"><table>', body)
body = body.replace("</table>", "</table></div>")
body = re.sub(r"<blockquote>\s*", '<aside class="note">', body)
body = body.replace("</blockquote>", "</aside>")
# Policies line in the appendix becomes a small chip row
body = re.sub(r"<p>Policies: <code>([^<]+)</code></p>", lambda m: '<p class="pol">Policies ' + "".join(
    f"<span>{p.strip()}</span>" for p in m.group(1).split(",")) + "</p>", body)

# Import files section
files_html = ['<h2 id="import-files">Import files</h2>',
              "<p>The three files that came with this manual. Downloads are blocked inside this page, so to recreate a file, "
              "copy it, save it as a plain-text file with the exact name shown, and upload it in <strong>Files</strong>.</p>"]
for name, desc in [("fo-cleanup-v1.rsc", "Removes the v1 setup. Import first."),
                   ("fo-install-v2.rsc", "Installs v2. Import second."),
                   ("fo-wg-import.rsc", "Saves your live VPN as a WireGuard profile.")]:
    code = (OUT / name).read_text().rstrip("\n")
    lines = code.count("\n") + 1
    files_html.append(f'<details class="file"><summary><span class="fname">{name}</span>'
                      f'<span class="fdesc">{desc} {lines} lines</span></summary>'
                      + code_block(code, "routeros", name) + "</details>")
body += "\n".join(files_html)

nav_items = []
for t in toc[0]["children"] if toc and toc[0]["level"] == 1 else toc:
    nav_items.append(f'<li><a href="#{t["id"]}">{html.escape(html.unescape(t["name"]))}</a></li>')
nav_items.append('<li><a href="#import-files">Import files</a></li>')
nav = "\n".join(nav_items)

CSS = (ROOT / "page.css").read_text()
JS = (ROOT / "page.js").read_text()

page = f"""<title>MikroTik Failover Manual</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans+Condensed:wght@500;600;700&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&display=swap">
<style>
{CSS}
</style>
<div class="wrap">
  <header class="masthead">
    <p class="eyebrow">Manual v2 · Starlink primary, MTN backup</p>
    <h1>Dual-WAN Failover, VPN Shield &amp; Voucher System</h1>
    <p class="lede">Sub-second Starlink to MTN failover with a configurable switch-back, a VPN shield with switchable WireGuard profiles, and a captive portal. Everything is set from one settings script.</p>
    <dl class="plate">
      <div><dt>RouterOS</dt><dd>7.24.x</dd></div>
      <div><dt>Router</dt><dd>hAP ac²</dd></div>
      <div><dt>WAN1</dt><dd>ether1 · Starlink</dd></div>
      <div><dt>WAN2</dt><dd>ether2 · MTN</dd></div>
      <div><dt>LAN</dt><dd>192.168.88.0/24</dd></div>
    </dl>
  </header>
  <div class="layout">
    <nav class="toc" aria-label="Contents">
      <details id="toc-toggle" open>
        <summary>Contents</summary>
        <ol>
{nav}
        </ol>
      </details>
    </nav>
    <main class="doc">
{body}
    </main>
  </div>
</div>
<script>
{JS}
</script>
"""
page = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '</head>\n<body>\n' + page + '</body>\n</html>\n')
(REPO / "docs" / "manual.html").write_text(page)
print("ok", len(page))
