# Playbooks

Where a section of *Hand-Me-Down Homelab* installs something, the book tells
you what I built and why. The playbook here is the build itself, written for
your AI assistant to carry out on **your** network.

| Playbook | Section | Builds | Tested |
|---|---|---|---|
| [`3.1-pihole.md`](3.1-pihole.md) | 3.1 Pi-hole: ad blocking and local names | Pi-hole v6 as the house's DNS resolver, with local names | 2026-10-08 |
| [`3.2-second-pihole.md`](3.2-second-pihole.md) | 3.2 Two Pi-holes that stay in sync | A second Pi-hole kept in step with the first by `3.2/pihole-sync.sh` | 2026-10-08 |
| [`3.3-proxy-manager.md`](3.3-proxy-manager.md) | 3.3 NGINX Proxy Manager: one front door | NPM in Docker, a proxy host with WebSockets, self-renewing certificates from your CA | 2026-10-09 |
| [`3.4-private-ca.md`](3.4-private-ca.md) | 3.4 Your own certificate authority | Step-CA with ACME, 90-day self-renewing certificates, trusted devices | 2026-10-09 |
| [`5.1-uptime-kuma.md`](5.1-uptime-kuma.md) | 5.1 Uptime Kuma | An independent monitor: HTTP(S), certificates, DNS, ping, push | 2026-10-09 |
| [`6.2-ollama-open-webui.md`](6.2-ollama-open-webui.md) | 6.2 Ollama and Open WebUI | One resident model as a network service, and a chat interface with login | 2026-10-09 (CPU only) |
| [`10.1-nextcloud.md`](10.1-nextcloud.md) | 10.1 Nextcloud | Private file sync on PostgreSQL and Redis, data on its own drive, reachable only over the tailnet | 2026-10-09 (tailnet step untested) |

## How to use one

1. **Read it first.** A playbook is a set of instructions an AI will carry
   out with your permissions. Look at it the way you'd look at an install
   script before running it.
2. **Give your AI the copy you read**, not the web address, so the file you
   read is the file that runs. Each playbook's short address is
   `handmedownhomelab.com/p/<name>`, e.g. `handmedownhomelab.com/p/3.1-pihole`.
   Releases are tagged if you'd rather work from a fixed version.
3. Start a session with your assistant (the book uses Claude Code; any
   capable assistant that can run commands will do), give it the file, and
   say: *"Follow this playbook. Ask me before every step marked CONFIRM."*
4. Answer its *Discover first* questions with your own values. Nothing in a
   playbook assumes the book's addresses or names.

No AI? Each playbook reads as a checklist. Do the steps yourself, using the
project's own install documentation.

## What every playbook contains

The same sections, in this order, so you know where to look:

- **Rules for the assistant:** discover before assuming, show every command
  and the machine it runs on, ask before risky steps, get current install
  commands from the project's own documentation, keep secrets off command
  lines, verify by effect.
- **Goal:** a checklist of what "done" looks like. It matches the book
  chapter's end-of-chapter checklist.
- **Discover first:** your values, found before anything is installed.
- **Steps:** each with the reason for it and a **Verify** check. Steps that
  change something important are marked **CONFIRM**.
- **Gotchas:** the book's war stories, turned into checks.
- **Rollback:** how to undo it.
- **Next:** where the book goes from here.

## How they're tested

Before a playbook is published, it is run on a clean machine (a fresh
container or virtual machine) and every **Verify** check has to pass. Its
header records what was tested, on what, and which steps were not
exercised. Whatever the test found was folded back into the playbook.

**Some can't be tested that way.** A playbook that needs an NVIDIA graphics
card is written from the author's working machine and the book, but a clean
test would mean taking that machine (it runs the cameras and the local AI
full-time) apart. Those playbooks say **Not tested** in their header and in
the table above. They have the same Verify checks; run them, and trust the
checks over the prose.
