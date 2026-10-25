# Playbooks

Where a section of *Hand-Me-Down Homelab* installs something, the book tells
you what I built and why. The playbook here is the build itself, written for
your AI assistant to carry out on **your** network.

| Playbook | Section | Builds | Tested |
|---|---|---|---|
| [`1.1-live-usb.md`](1.1-live-usb.md) | 1.1 The hardware pile | A Linux Mint live USB, booted on the old machine without touching its disk, and the appraisal run from it | **Not tested** (needs a spare PC; written from Linux Mint's and balenaEtcher's documentation) |
| [`1.2-proxmox-mac-mini.md`](1.2-proxmox-mac-mini.md) | 1.2 Proxmox on a 2012 Mac mini | Proxmox VE on an old PC or Intel Mac, with a working fan curve | Partly: install tested; Mac steps **Not tested** (need a Mac) |
| [`1.4-backups.md`](1.4-backups.md) | 1.4 Backups that tell you if they fail | USB backups that refuse to fill the root disk, heal themselves, and get copied off the host | 2026-10-09 (nested Proxmox) |
| [`1.5-cutover-day.md`](1.5-cutover-day.md) | 1.5 The gateway, and DHCP reservations as code | A new gateway set up on the bench, a short cutover in the right order, and reservations kept in a table and loaded by a dry-run-first script | Partly: the loader offline, and read-only against the author's gateway; the cutover **Not tested** (needs a spare gateway) |
| [`1.6-iot-vlan.md`](1.6-iot-vlan.md) | 1.6 An IoT VLAN, and the camera VLAN I canceled | A network of its own for smart-home gadgets, firewall rules, the Wi-Fi name moved instead of the devices, containment tested from inside | **Not tested** (needs a VLAN-capable gateway; written from the author's migration) |
| [`2.1-llm-wiki.md`](2.1-llm-wiki.md) | 2.1 The LLM wiki: a lab that documents itself | A markdown wiki your AI maintains: schema, four page types, index, to-do list, log, and ingest, query and lint | 2026-10-20 |
| [`2.2-wiki-git-hub.md`](2.2-wiki-git-hub.md) | 2.2 One wiki on every machine | A git hub for the wiki, a clone everywhere, and Claude Code hooks that pull and push | 2026-10-09 |
| [`2.3-claude-sysadmin.md`](2.3-claude-sysadmin.md) | 2.3 Claude Code as sysadmin: SSH, skills, memory, hooks | Claude Code with a global rules file, key-only SSH under one username, a sudo rule, a read-only update-check skill, and an MCP inventory | 2026-10-20 (login and interactive commands not exercised) |
| [`2.4-auto-memory.md`](2.4-auto-memory.md) | 2.4 Teaching the AI from its mistakes: the memory file | Lessons as rules indexed by the moment they matter, one memory on every workstation, and a weekly read-only check | 2026-10-20 |
| [`2.5-homelab-menu.md`](2.5-homelab-menu.md) | 2.5 The Homelab Menu and audit.sh | A one-letter launcher for your hosts and commands, and one report from every host | 2026-10-20 |
| [`3.1-uptime-kuma.md`](3.1-uptime-kuma.md) | 3.1 Uptime Kuma | An independent monitor: HTTP(S), certificates, DNS, ping, push | 2026-10-09 |
| [`3.2-syslog-disk-alerts.md`](3.2-syslog-disk-alerts.md) | 3.2 Central syslog, and disk-health alerts | A central syslog collector with 90-day retention, and SMART alerts proven to arrive | 2026-10-09 |
| [`3.3-mail-relay.md`](3.3-mail-relay.md) | 3.3 Email that actually arrives | A send-only Postfix relay through your mail provider | 2026-10-09 (to the provider's login) |
| [`3.4-ai-alert-triage.md`](3.4-ai-alert-triage.md) | 3.4 The 06:32 triage | An archive of the lab's alert mail pulled read-only, a daily headless triage with no tools, missing reports caught by code, a push only when something needs you, a daily All OK | 2026-10-23 (LXC with a local mailbox; model call over synthetic mail; push and a real provider **Not tested**) |
| [`3.5-update-sweeps.md`](3.5-update-sweeps.md) | 3.5 Update sweeps without breaking things | Package lists that refresh daily and are proven fresh, simulated upgrades, Docker by digest, and an apply that checks for deleted libraries | 2026-10-23 (Debian 13 LXC) |
| [`4.1-home-assistant-vm.md`](4.1-home-assistant-vm.md) | 4.1 Home Assistant in a Proxmox VM | Home Assistant OS as a VM, claimed by you, behind the proxy, with Mosquitto | 2026-10-09 (add-ons in the UI untested) |
| [`4.2-zigbee-and-door-chime.md`](4.2-zigbee-and-door-chime.md) | 4.2 Zigbee buttons, door sensors, and a door chime | A coordinator passed through to the VM, a channel clear of the Wi-Fi, buttons keyed on `zha_event` and the IEEE address, a local spoken door chime, a safe way to retire devices | **Not tested** (needs Zigbee hardware; written from the author's working setup) |
| [`4.3-mmwave-stair-lights.md`](4.3-mmwave-stair-lights.md) | 4.3 mmWave radar stair lights with ESPHome | An LD2450 radar on an ESP32 with ESPHome, stair lights on while anyone is on them, zones trimmed, the YAML in git | **Not tested** (needs the radar and board; written from the author's working sensor) |
| [`4.4-wled-holiday-lights.md`](4.4-wled-holiday-lights.md) | 4.4 WLED: garage and holiday porch lights | Fused 12 V sections fed at the centre, WLED on a wired IoT network, the settings that matter, seasonal presets on a schedule, troubleshooting that reads WLED's real state first | **Not tested** (needs the strips and controller; written from the author's working installation) |
| [`5.1-energy-water-dashboards.md`](5.1-energy-water-dashboards.md) | 5.1 Dashboards I: the main home, energy and water | A main-home dashboard in the sections view, the Energy dashboard without double-counting, a daily meter per plug, and a Water dashboard that finds every leak sensor by device class | 2026-10-25 (throwaway Home Assistant in a container, stand-in sensors; real hardware and phone rendering **Not tested**) |
| [`5.2-glances-systems-dashboard.md`](5.2-glances-systems-dashboard.md) | 5.2 Dashboards II: servers, air and climate, TV and the family logbook | Proxmox through a read-only user, a pinned Glances agent firewalled to Home Assistant only, a Systems dashboard with one row per host, and cards for climate and your own data | 2026-10-25 (Glances and its firewall on a Debian LXC; the Proxmox VE integration, Macs and Nest **Not tested**) |
| [`5.5-ha-mcp.md`](5.5-ha-mcp.md) | 5.5 Claude drives Home Assistant through MCP | ha-mcp in Claude Code with its own token, starting in Read Only Mode | 2026-10-09 (reads only) |
| [`6.1-pihole.md`](6.1-pihole.md) | 6.1 Pi-hole: ad blocking and local names | Pi-hole v6 as the house's DNS resolver, with local names | 2026-10-08 |
| [`6.2-second-pihole.md`](6.2-second-pihole.md) | 6.2 Two Pi-holes that stay in sync | A second Pi-hole kept in step with the first by `6.2/pihole-sync.sh` | 2026-10-08 |
| [`6.3-proxy-manager.md`](6.3-proxy-manager.md) | 6.3 NGINX Proxy Manager: one front door | NPM in Docker, a proxy host with WebSockets, self-renewing certificates from your CA | 2026-10-09 |
| [`6.4-private-ca.md`](6.4-private-ca.md) | 6.4 Your own certificate authority | Step-CA with ACME, 90-day self-renewing certificates, trusted devices | 2026-10-09 |
| [`6.5-tailscale.md`](6.5-tailscale.md) | 6.5 Tailscale | Your devices on a tailnet, a subnet router, tailnet DNS, no open ports | 2026-10-09 |
| [`7.1-gpu-box.md`](7.1-gpu-box.md) | 7.1 Building the GPU box | Mint with an NVIDIA driver for your card, persistence mode, Docker and the Container Toolkit, a firewall that covers Docker's ports, updates that leave the GPU stack alone | **Not tested** (needs a spare NVIDIA card; written from the author's working machine) |
| [`7.2-ollama-open-webui.md`](7.2-ollama-open-webui.md) | 7.2 Ollama and Open WebUI | One resident model as a network service, and a chat interface with login | 2026-10-09 (CPU only) |
| [`7.3-forge-flux.md`](7.3-forge-flux.md) | 7.3 Forge and FLUX | Forge Neo with FLUX.1 [dev], a launcher that frees the card first, a tunnel instead of an open port, and a Claude Code skill that looks at its own images | **Not tested** (needs the GPU; written from the author's working machine) |
| [`7.4-comfyui.md`](7.4-comfyui.md) | 7.4 ComfyUI: text and photos to video | ComfyUI in its own venv, a launcher that frees the card first, Wan 2.2 and LTX-Video, and a Claude Code skill that renders and looks at frames | **Not tested** (needs the GPU; written from the author's working machine) |
| [`7.6-ace-step.md`](7.6-ace-step.md) | 7.6 ACE-Step: whole songs on your own GPU | ACE-Step v1 with CPU offload, a web interface behind an SSH tunnel, a launcher that frees the card first, and batches from a job file | **Not tested** (needs the GPU; written from the author's working machine) |
| [`8.1-hermes-agent.md`](8.1-hermes-agent.md) | 8.1 Hermes: a sandboxed AI agent | Hermes in its own VM on your own model server, a page watcher on its scheduler, wiki copies through a write-only rrsync jail | 2026-10-10 (LXC, small model on another machine's Ollama; channels **Not tested**) |
| [`9.1-nextcloud.md`](9.1-nextcloud.md) | 9.1 Nextcloud | Private file sync on PostgreSQL and Redis, data on its own drive, reachable only over the tailnet | 2026-10-09 (tailnet step untested) |
| [`9.3-openwebrx.md`](9.3-openwebrx.md) | 9.3 OpenWebRX: a web radio receiver on a Pi Zero | OpenWebRX+ on a Pi with an RTL-SDR, an admin login, profiles each proved on a real signal, the antenna cut per band, and the dongle's accuracy measured | **Not tested** (needs the radio hardware; written from the author's receiver) |
| [`10.1-frigate.md`](10.1-frigate.md) | 10.1 A video recorder plus Frigate | Frigate in Docker on your recorder's streams, a YOLOv9 model checked on a known image, events to MQTT, a login on 8971 | 2026-10-10 (CPU only, test stream; GPU image and CUDA cache **Not tested**) |
| [`10.4-speed-camera-pi.md`](10.4-speed-camera-pi.md) | 10.4 A portable speed camera | A Pi 3B and PS3 Eye measuring speeds by frame differencing, a clock it can trust offline, key-only SSH, aimed through a tunnel, calibrated per lane, writing the fixed camera's CSV | **Not tested** (needs the hardware; built and bench-tested on the author's unit; street calibration not yet done) |
| [`11.2-suricata-evebox.md`](11.2-suricata-evebox.md) | 11.2 Suricata and EveBox | A passive IDS sensor proven to see traffic and alert, with EveBox behind a login | 2026-10-09 (container, not a Pi) |
| [`11.4-kismet.md`](11.4-kismet.md) | 11.4 Kismet: passive Wi-Fi monitoring | Kismet on a monitor-mode adapter, hop rate and channels measured, LAN-only web interface behind TLS, logs and memory bounded, a watchdog that repairs the hop list and pushes to Kuma | **Not tested** (needs the adapter; written from the author's sensor) |

## How to use one

1. **Read it first.** A playbook is a set of instructions an AI will carry
   out with your permissions. Look at it the way you'd look at an install
   script before running it.
2. **Give your AI the copy you read**, not the web address, so the file you
   read is the file that runs. Each playbook's short address is
   `handmedownhomelab.com/p/<name>`, e.g. `handmedownhomelab.com/p/6.1-pihole`.
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
full-time) apart. A playbook that needs hardware a container can't have (a
radio, a Zigbee stick, a sensor board, LED strips) is written from the
author's working build in the same way. Those playbooks say **Not tested**
in their header and in the table above. They have the same Verify checks; run them, and trust the
checks over the prose.
