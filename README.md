# Hand-Me-Down Homelab — companion files

Scripts from the book *Hand-Me-Down Homelab: How I built a home lab from old
hardware — and an AI runs it*. Folders are named after the book's sections.

**The book** is on Leanpub as a PDF and EPUB, with free updates. The
Introduction and Chapter 1 are a free sample:
[leanpub.com/handmedownhomelab](https://leanpub.com/handmedownhomelab).

| File | Section | What it does |
|---|---|---|
| [`1.2/install-mbpfan.sh`](1.2/install-mbpfan.sh) | 1.2 Proxmox on a 2012 Mac mini | Gives a Mac running Linux a working fan curve, with a restart guard |
| [`1.2/10-restart.conf`](1.2/10-restart.conf) | 1.2 | The systemd drop-in that restarts `mbpfan` if it dies |
| [`1.4/proxmox-backup-sync.sh`](1.4/proxmox-backup-sync.sh) | 1.4 Backups | Nightly copy of a Proxmox host's backups to another machine; refuses when the source looks wrong |
| [`1.5/ux7_load_reservations.py`](1.5/ux7_load_reservations.py) | 1.5 The gateway, and DHCP reservations as code | Loads DHCP reservations from a Markdown table onto a UniFi gateway; dry run by default |
| [`1.5/reservations.example.md`](1.5/reservations.example.md) | 1.5 | An example table to start from |
| [`2.2/post-receive`](2.2/post-receive), [`2.2/wiki-sync.sh`](2.2/wiki-sync.sh), [`2.2/check-wiki-log.sh`](2.2/check-wiki-log.sh), [`2.2/settings-hooks.json`](2.2/settings-hooks.json) | 2.2 One wiki on four machines | The hub's update hook, and the Claude Code hooks that pull at session start, push at the end, and check for log entries |
| [`2.5/ssh-menu.sh`](2.5/ssh-menu.sh), [`2.5/m.zsh`](2.5/m.zsh) | 2.5 The Homelab Menu and `audit.sh` | A one-letter launcher for your hosts and frequent commands |
| [`2.5/audit.sh`](2.5/audit.sh) | 2.5 | Runs the same commands on every host and prints one report |
| [`3.2/10-remote-collector.conf`](3.2/10-remote-collector.conf), [`3.2/prune-remote-logs.sh`](3.2/prune-remote-logs.sh) + `.service` / `.timer` | 3.2 Syslog | The central collector, and 90-day retention |
| [`3.2/60-forward-to-syslog.conf`](3.2/60-forward-to-syslog.conf) | 3.2 | Forwards a host's logs to the collector over TCP |
| [`6.2/pihole-sync.sh`](6.2/pihole-sync.sh) | 6.2 Two Pi-holes that stay in sync | One-way sync from a primary Pi-hole to a secondary, only when something changed |
| [`6.3/server_proxy.conf`](6.3/server_proxy.conf) | 6.3 NGINX Proxy Manager | Answers the ACME challenge on every proxy host, even with Force SSL on |
| [`7.3/forge-run.sh`](7.3/forge-run.sh), [`7.3/forge.zsh`](7.3/forge.zsh) | 7.3 Forge and FLUX | Start Forge only after freeing the GPU, through an SSH tunnel; Ctrl-C loads the chat model back |
| [`7.3/forge-image/`](7.3/forge-image/) | 7.3 | A Claude Code skill: generate with Forge, look at the image, critique, go again |
| [`7.4/comfyui-run.sh`](7.4/comfyui-run.sh), [`7.4/comfy.zsh`](7.4/comfy.zsh) | 7.4 ComfyUI | Start ComfyUI only after freeing the GPU, through an SSH tunnel; Ctrl-C loads the chat model back |
| [`7.4/comfyui-video/`](7.4/comfyui-video/) | 7.4 | A Claude Code skill: Wan 2.2 or LTX-Video clips from text or a still, longer clips by chaining, frames pulled and critiqued; four API-format templates |
| [`7.6/acestep-run.sh`](7.6/acestep-run.sh), [`7.6/music.zsh`](7.6/music.zsh) | 7.6 ACE-Step | Start ACE-Step only after freeing the GPU, offload on, through an SSH tunnel; Ctrl-C loads the chat model back |
| [`7.6/acestep_batch.py`](7.6/acestep_batch.py) | 7.6 | Several tracks from a job file, without the web interface |
| [`8.1/watch_page.py`](8.1/watch_page.py) | 8.1 Hermes | A page watcher for a Hermes script-only cron job: silent until the page changes |
| [`10.1/config.yml`](10.1/config.yml) | 10.1 A video recorder plus Frigate | Frigate: one camera, GPU detection, recording, a speed zone |
| [`10.2/frigate-detect-watchdog.py`](10.2/frigate-detect-watchdog.py) + `.service` / `.timer` | 10.2 Blind for 45 hours | Emails when Frigate is "healthy" but detecting nothing |
| [`10.2/frigate-safe-restart.sh`](10.2/frigate-safe-restart.sh), [`10.2/free-ollama-vram.sh`](10.2/free-ollama-vram.sh) | 10.2 | Restart Frigate on a shared GPU, and prove the detector came back |
| [`10.4/`](10.4/) | 10.4 A portable speed camera | The whole build: provisioning, key-only SSH, the speed-camera plugin, a clock check that refuses a wrong clock, exposure lock and tuning, an aiming preview, and a CSV exporter. Start with its README |
| [`11.3/threshold.config`](11.3/threshold.config) | 11.3 Tuning, and the daily AI digest | Suricata suppressions and rate limits, each with its reason |
| [`11.4/kismet_site.conf`](11.4/kismet_site.conf), [`11.4/99-kismet-unmanaged.conf`](11.4/99-kismet-unmanaged.conf), [`11.4/kismet.service`](11.4/kismet.service) | 11.4 Kismet | The site config with every setting explained, NetworkManager kept off the capture radio, the service |
| [`11.4/kismet-hop-watch`](11.4/kismet-hop-watch) + `.service` / `.timer` | 11.4 | Puts the channel list back when Kismet drops it, and pushes a heartbeat to Uptime Kuma only while capture is healthy |
| [`11.4/kismet-log-maintenance.sh`](11.4/kismet-log-maintenance.sh) | 11.4 | Prunes Kismet's per-run logs, where logrotate can't |

## Playbooks and links

- **[`playbooks/`](playbooks/)**: where a section installs something, its
  playbook is a tested build for your AI assistant to carry out on your own
  network. Start with [`playbooks/README.md`](playbooks/README.md).
- **[`LINKS.md`](LINKS.md)**: every program the book uses, with its
  website (the book's Appendix E).
- **[`ERRATA.md`](ERRATA.md)**: corrections to the book's text, by edition
  and section.

## Before you run anything

- **Read the script first.** Each one explains at the top what it does, what
  it needs and how to install it. The book explains why.
- **Edit the settings for your network.** Addresses and host names are the
  book's examples, not yours. `ux7_load_reservations.py` has a marked
  *YOUR NETWORK* block.
- **Dry run where there is one.** The reservation loader writes nothing
  without `--apply`, including when pruning.
- **No secrets in here, and none in your copy.** Passwords go in a root-only
  file, an environment variable or the macOS Keychain, never on a command line
  or in the script.

## License

MIT. See [LICENSE](LICENSE). Use them, change them, share them.
