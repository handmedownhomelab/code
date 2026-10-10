# Software and where to get it

Every program, service and AI model in *Hand-Me-Down Homelab*, with the
project's own website and the book section that sets it up. Get software
from these sites, not from a search result or a mirror. Links checked
2026-10-08. The book prints the same list as Appendix E.

Not listed: what the author wrote for this lab (LanScan, Photo Intel,
HomelabMenu, the Homelab Menu and audit.sh). The book describes them, and
this repository holds the parts worth reusing.

## Part I — Foundations

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Proxmox VE](https://proxmox.com) | Hypervisor: virtual machines and containers on old hardware | 1.2 | [`1.2-proxmox-mac-mini.md`](playbooks/1.2-proxmox-mac-mini.md) |
| [mbpfan](https://github.com/linux-on-mac/mbpfan) | A working fan curve for a Mac running Linux | 1.2 | [`1.2-proxmox-mac-mini.md`](playbooks/1.2-proxmox-mac-mini.md) |
| [UniFi Network](https://ui.com) | The gateway, switches, access points and DHCP | 1.5 |  |
| [Git](https://git-scm.com) | Keeps the wiki's history and syncs it between machines | 2.1 | [`2.2-wiki-git-hub.md`](playbooks/2.2-wiki-git-hub.md) |
| [Obsidian](https://obsidian.md) | Reads and edits the wiki as linked notes | 2.1 |  |
| [Claude Code](https://code.claude.com/docs) | The AI assistant that does most of the work | 2.3 |  |
| [*LLM Wiki* (Andrej Karpathy)](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) | The write-up the wiki pattern comes from; the brief I gave Claude | 2.1 |  |
| [*Andrej Karpathy Just 10x'd Everyone's Claude Code* (Nate Herk)](https://youtube.com/watch?v=sboNwYmH3AY) | The video that introduced me to it | 2.1 |  |
| [Uptime Kuma](https://uptime.kuma.pet) | Monitoring and alerts | 3.1 | [`3.1-uptime-kuma.md`](playbooks/3.1-uptime-kuma.md) |
| [rsyslog](https://rsyslog.com) | Collects every machine's logs in one place | 3.2 | [`3.2-syslog-disk-alerts.md`](playbooks/3.2-syslog-disk-alerts.md) |
| [smartmontools](https://smartmontools.org) | Disk health checks and alerts | 3.2 | [`3.2-syslog-disk-alerts.md`](playbooks/3.2-syslog-disk-alerts.md) |
| [Postfix](https://postfix.org) | Sends the lab's email alerts through a mail relay | 3.3 | [`3.3-mail-relay.md`](playbooks/3.3-mail-relay.md) |

## Part II — Your network

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Pi-hole](https://pi-hole.net) | DNS resolver, local names and ad blocking | 4.1 | [`4.1-pihole.md`](playbooks/4.1-pihole.md) |
| [NGINX Proxy Manager](https://nginxproxymanager.com) | One front door for every web interface | 4.3 | [`4.3-proxy-manager.md`](playbooks/4.3-proxy-manager.md) |
| [acme.sh](https://github.com/acmesh-official/acme.sh) | Requests and renews certificates | 4.3 | [`4.4-private-ca.md`](playbooks/4.4-private-ca.md) |
| [step-ca](https://smallstep.com/docs/step-ca) | Your own certificate authority | 4.4 | [`4.4-private-ca.md`](playbooks/4.4-private-ca.md) |
| [Tailscale](https://tailscale.com) | Remote access with no open ports | 4.5 | [`4.5-tailscale.md`](playbooks/4.5-tailscale.md) |

## Part III — The smart home

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Home Assistant](https://home-assistant.io) | Runs the smart home | 5.1 | [`5.1-home-assistant-vm.md`](playbooks/5.1-home-assistant-vm.md) |
| [Mosquitto](https://mosquitto.org) | The MQTT message broker | 5.1 | [`5.1-home-assistant-vm.md`](playbooks/5.1-home-assistant-vm.md) |
| [MQTT Explorer](https://mqtt-explorer.com) | Watches MQTT messages go by, for debugging | 5.1 |  |
| [HACS](https://hacs.xyz) | The Home Assistant Community Store | 5.1 |  |
| [Piper](https://github.com/rhasspy/piper) | Local text-to-speech: the door-chime voice | 5.2 |  |
| [ESPHome](https://esphome.io) | Firmware for small sensor boards | 5.3 |  |
| [WLED](https://kno.wled.ge) | Firmware for addressable LED strips | 5.4 |  |
| [Glances](https://nicolargo.github.io/glances) | A monitoring agent for the hosts that aren't Proxmox | 6.2 |  |
| [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) | Lets an AI assistant work Home Assistant's tools | 6.5 | [`6.5-ha-mcp.md`](playbooks/6.5-ha-mcp.md) |
| [Whisper (Wyoming add-on)](https://github.com/rhasspy/wyoming-faster-whisper) | Speech to text for Home Assistant's voice assistant | 6.5 |  |
| [Extended OpenAI Conversation](https://github.com/jekalmin/extended_openai_conversation) | Hands Assist's requests to any OpenAI-compatible agent | 6.5 |  |

## Part IV — Your own AI, and apps

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Linux Mint](https://linuxmint.com) | The GPU tower's operating system | 7.1 |  |
| [NVIDIA driver](https://nvidia.com/en-us/drivers) | Runs the graphics card | 7.1 |  |
| [Docker Engine](https://docs.docker.com/engine/install) | Runs the AI apps in containers | 7.1 |  |
| [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit) | Gives containers the graphics card | 7.1 |  |
| [Ollama](https://ollama.com) | Runs language models locally | 7.2 | [`7.2-ollama-open-webui.md`](playbooks/7.2-ollama-open-webui.md) |
| [Open WebUI](https://openwebui.com) | A private chat interface for Ollama | 7.2 | [`7.2-ollama-open-webui.md`](playbooks/7.2-ollama-open-webui.md) |
| [Gemma 4](https://ollama.com/library/gemma4) | The local language model most of the lab uses | 7.2, 8.5 |  |
| [Brave Search API](https://brave.com/search/api) | Web search for the chat interface | 7.2 |  |
| [Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic) | A web interface and API for image models | 7.3 |  |
| [FLUX.1 [dev]](https://huggingface.co/black-forest-labs/FLUX.1-dev) | The image model | 7.3 |  |
| [ComfyUI](https://comfy.org) | Node-based workflows for video models and photo editing | 7.4 |  |
| [LTX-Video](https://github.com/Lightricks/LTX-Video) | Fast text and photo to video | 7.4 |  |
| [Wan 2.2](https://github.com/Wan-Video/Wan2.2) | Text and photo to video | 7.4 |  |
| [HunyuanVideo 1.5](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5) | Longer clips that hold a subject's identity | 7.4 |  |
| [FLUX.1 Kontext [dev]](https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev) | Edits photos from a typed instruction | 7.5 |  |
| [ACE-Step](https://github.com/ace-step/ACE-Step) | Generates whole songs | 7.6 |  |
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) | A sandboxed AI agent on local models | 8.1 |  |
| [Photon](https://photon.codes) | Connects the agent to iMessage | 8.2 |  |
| [BlueBubbles](https://bluebubbles.app) | The iMessage bridge Photon replaced | 8.2 |  |
| [osxphotos](https://github.com/RhetTbull/osxphotos) | Exports photos and their data from Apple Photos | 8.4 |  |
| [Qwen3-VL](https://ollama.com/library/qwen3-vl) | A vision model, for describing video frames | 8.5 |  |
| [DeepSeek-OCR](https://huggingface.co/deepseek-ai/DeepSeek-OCR) | Transcribes text in photos: plaques, menus, signs | 8.5 |  |
| [Nextcloud](https://nextcloud.com) | Private file sync | 9.1 | [`9.1-nextcloud.md`](playbooks/9.1-nextcloud.md) |
| [faster-whisper](https://github.com/SYSTRAN/faster-whisper) | Transcribes the home movies | 9.2 |  |
| [Plex](https://plex.tv) | Plays the home movies on every screen | 9.2 |  |
| [HDHomeRun](https://silicondust.com) | Over-the-air live TV and DVR for Plex | 9.2 |  |
| [OpenWebRX+](https://github.com/luarvique/openwebrx) | A web radio receiver | 9.3 |  |

## Part V — Security

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Frigate](https://frigate.video) | Camera recording and AI object detection | 10.1 |  |
| [Raspberry Pi OS](https://raspberrypi.com/software) | The Raspberry Pis' operating system | 10.4 |  |
| [speed-camera (pageauc)](https://github.com/pageauc/speed-camera) | Frame-differencing speed measurement for the portable camera | 10.4 |  |
| [nmap](https://nmap.org) | Host discovery for LanScan's hourly sweep | 11.1 |  |
| [Suricata](https://suricata.io) | Intrusion detection | 11.2 | [`11.2-suricata-evebox.md`](playbooks/11.2-suricata-evebox.md) |
| [EveBox](https://evebox.org) | A web interface for Suricata's alerts | 11.2 | [`11.2-suricata-evebox.md`](playbooks/11.2-suricata-evebox.md) |
| [Emerging Threats open ruleset](https://rules.emergingthreats.net) | The IDS rules, refreshed nightly | 11.2 |  |
| [Kismet](https://kismetwireless.net) | Passive Wi-Fi monitoring | 11.4 |  |
