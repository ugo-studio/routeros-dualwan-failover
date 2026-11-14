#!/usr/bin/env python3
"""Fails (exit 1) if any tracked text file looks like it contains a secret.

Checks for WireGuard-style base64 keys, private key blocks and email
addresses. Placeholders such as PRIVATE_KEY are fine.
"""
import pathlib, re, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parent.parent
PATTERNS = {
    "WireGuard-style key": re.compile(r"(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=(?![A-Za-z0-9+/=])"),
    "private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "email address": re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "PrivateKey line": re.compile(r"PrivateKey\s*=\s*[A-Za-z0-9+/]{20,}"),
}
ALLOWED_EMAILS = {"noreply@github.com"}

try:
    files = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                           cwd=REPO, capture_output=True, text=True, check=True).stdout.split()
except Exception:
    files = [str(p.relative_to(REPO)) for p in REPO.rglob("*") if p.is_file() and ".git" not in p.parts]

problems = []
for name in files:
    path = REPO / name
    try:
        text = path.read_text()
    except (UnicodeDecodeError, FileNotFoundError):
        continue
    for label, rx in PATTERNS.items():
        for m in rx.finditer(text):
            if label == "email address" and (m.group() in ALLOWED_EMAILS or m.group().endswith("@users.noreply.github.com")):
                continue
            line = text.count("\n", 0, m.start()) + 1
            problems.append(f"{name}:{line}: {label}")

if problems:
    print("Possible secrets found:\n  " + "\n  ".join(problems))
    sys.exit(1)
print(f"check_secrets: {len(files)} files clean")
