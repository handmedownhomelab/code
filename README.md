# Hand-Me-Down Homelab — companion files

Scripts from the book *Hand-Me-Down Homelab: How I built a home lab from old
hardware — and an AI runs it*. Folders are named after the book's sections.

| File | Section | What it does |
|---|---|---|
| [`1.2/install-mbpfan.sh`](1.2/install-mbpfan.sh) | 1.2 Proxmox on a 2012 Mac mini | Gives a Mac running Linux a working fan curve, with a restart guard |
| [`1.2/10-restart.conf`](1.2/10-restart.conf) | 1.2 | The systemd drop-in that restarts `mbpfan` if it dies |
| [`1.4/ux7_load_reservations.py`](1.4/ux7_load_reservations.py) | 1.4 The gateway, and DHCP reservations as code | Loads DHCP reservations from a Markdown table onto a UniFi gateway; dry run by default |
| [`1.4/reservations.example.md`](1.4/reservations.example.md) | 1.4 | An example table to start from |
| [`2.5/ssh-menu.sh`](2.5/ssh-menu.sh), [`2.5/m.zsh`](2.5/m.zsh) | 2.5 The Homelab Menu and `audit.sh` | A one-letter launcher for your hosts and frequent commands |
| [`2.5/audit.sh`](2.5/audit.sh) | 2.5 | Runs the same commands on every host and prints one report |
| [`3.2/pihole-sync.sh`](3.2/pihole-sync.sh) | 3.2 Two Pi-holes that stay in sync | One-way sync from a primary Pi-hole to a secondary, only when something changed |
| [`7.1/config.yml`](7.1/config.yml) | 7.1 A video recorder plus Frigate | Frigate: one camera, GPU detection, recording, a speed zone |
| [`7.2/frigate-detect-watchdog.py`](7.2/frigate-detect-watchdog.py) + `.service` / `.timer` | 7.2 Blind for 45 hours | Emails when Frigate is "healthy" but detecting nothing |
| [`7.2/frigate-safe-restart.sh`](7.2/frigate-safe-restart.sh), [`7.2/free-ollama-vram.sh`](7.2/free-ollama-vram.sh) | 7.2 | Restart Frigate on a shared GPU, and prove the detector came back |
| [`8.3/threshold.config`](8.3/threshold.config) | 8.3 Tuning, and the daily AI digest | Suricata suppressions and rate limits, each with its reason |

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
