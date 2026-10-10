"""watch_page.py — Hand-Me-Down Homelab, section 8.1.

Watch one web page and print a line only when it changes. Written for a
Hermes Agent script-only cron job (no LLM): empty stdout is a silent tick,
any stdout becomes one message to the job's delivery target.

Install as ~/.hermes/scripts/watch_page.py, set URL and NAME, then:
  hermes cron create "every 30m" --no-agent --script watch_page.py \
      --deliver local --name <NAME>

Most real pages change on every load (timestamps, ads, session tokens), so
hash only the part you care about: cut `body` down to it before hashing.
The first run records a baseline silently. Diagnostics (a failed fetch) go
to stderr, which never triggers a delivery, so a flaky site doesn't page
you. Tested 2026-10-10 on Hermes Agent v0.21.6.
"""
import hashlib, json, sys, urllib.request
from pathlib import Path

URL = "https://example.com/the-page-to-watch"     # the page to watch
NAME = "example-page"                              # one state file per watcher
STATE = Path.home() / ".hermes" / "watcher-state" / f"{NAME}.json"

try:
    body = urllib.request.urlopen(URL, timeout=20).read()
except Exception as e:                             # a failed fetch is not a change
    print(f"fetch failed: {e}", file=sys.stderr)
    sys.exit(0)
digest = hashlib.sha256(body).hexdigest()
old = json.loads(STATE.read_text())["sha256"] if STATE.exists() else None
STATE.parent.mkdir(parents=True, exist_ok=True)
STATE.write_text(json.dumps({"sha256": digest}))
if old and old != digest:
    print(f"Page watcher - {NAME}: {URL} changed")  # the message names its sender
