# Software and where to get it

Every program, service and AI model in *Hand-Me-Down Homelab*, with the
project's own website and the book section that sets it up. Get software
from these sites, not from a search result or a mirror. Links checked
2026-10-08. The book prints the same list as Appendix E.

## Part I — Foundations

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Proxmox VE](https://proxmox.com) | Hypervisor: virtual machines and containers on old hardware | 1.2 |  |
| [mbpfan](https://github.com/linux-on-mac/mbpfan) | A working fan curve for a Mac running Linux | 1.2 |  |
| [Postfix](https://postfix.org) | Sends the lab's email alerts through a mail relay | 1.2 |  |
| [UniFi Network](https://ui.com) | The gateway, switches, access points and DHCP | 1.4 |  |
| [ESPHome](https://esphome.io) | Firmware for small sensor boards | 1.5 |  |
| [WLED](https://kno.wled.ge) | Firmware for addressable LED strips | 1.5 |  |
| [Git](https://git-scm.com) | Keeps the wiki's history and syncs it between machines | 2.1 |  |
| [Obsidian](https://obsidian.md) | Reads and edits the wiki as linked notes | 2.1 |  |
| [Claude Code](https://code.claude.com/docs) | The AI assistant that does most of the work | 2.3 |  |

## Part II — Your network

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Pi-hole](https://pi-hole.net) | DNS resolver, local names and ad blocking | 3.1 | [`3.1-pihole.md`](playbooks/3.1-pihole.md) |
| [NGINX Proxy Manager](https://nginxproxymanager.com) | One front door for every web interface | 3.3 |  |
| [acme.sh](https://github.com/acmesh-official/acme.sh) | Requests and renews certificates | 3.3 |  |
| [step-ca](https://smallstep.com/docs/step-ca) | Your own certificate authority | 3.4 |  |
| [Tailscale](https://tailscale.com) | Remote access with no open ports | 3.5 |  |

## Part III — The smart home

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Home Assistant](https://home-assistant.io) | Runs the smart home | 4.1 |  |
| [Mosquitto](https://mosquitto.org) | The MQTT message broker | 4.1 |  |
| [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) | Lets an AI assistant work Home Assistant's tools | 4.9 |  |
| [Whisper](https://github.com/SYSTRAN/faster-whisper) | Speech to text, for voice commands | 4.9, 10.2 |  |

## Part IV — Keeping it running

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Uptime Kuma](https://uptime.kuma.pet) | Monitoring and alerts | 5.1 |  |
| [rsyslog](https://rsyslog.com) | Collects every machine's logs in one place | 5.2 |  |
| [smartmontools](https://smartmontools.org) | Disk health checks and alerts | 5.2 |  |

## Part V — Your own AI

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Linux Mint](https://linuxmint.com) | The GPU tower's operating system | 6.1 |  |
| [NVIDIA driver](https://nvidia.com/en-us/drivers) | Runs the graphics card | 6.1 |  |
| [Docker Engine](https://docs.docker.com/engine/install) | Runs the AI apps in containers | 6.1 |  |
| [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit) | Gives containers the graphics card | 6.1 |  |
| [Ollama](https://ollama.com) | Runs language models locally | 6.2 |  |
| [Open WebUI](https://openwebui.com) | A private chat interface for Ollama | 6.2 |  |
| [Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic) | A web interface and API for image models | 6.3 |  |
| [FLUX.1 [dev]](https://huggingface.co/black-forest-labs/FLUX.1-dev) | The image model | 6.3 |  |
| [ComfyUI](https://comfy.org) | Node-based workflows for video models | 6.4 |  |
| [Wan 2.2](https://github.com/Wan-Video/Wan2.2) | Text and photo to video | 6.4 |  |
| [LTX-Video](https://github.com/Lightricks/LTX-Video) | Fast text and photo to video | 6.4 |  |
| [FLUX.1 Kontext [dev]](https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev) | Edits photos from a typed instruction | 6.5 |  |
| [ACE-Step](https://github.com/ace-step/ACE-Step) | Generates whole songs | 6.6 |  |
| [Gemma 4](https://ollama.com/library/gemma4) | The local language model most of the lab uses | 6.2, 7.5 |  |
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) | A sandboxed AI agent on local models | 7.1 |  |
| [Photon](https://photon.codes) | Connects the agent to iMessage | 7.2 |  |
| [BlueBubbles](https://bluebubbles.app) | The iMessage bridge Photon replaced | 7.2 |  |
| [osxphotos](https://github.com/RhetTbull/osxphotos) | Exports photos and their data from Apple Photos | 7.4 |  |
| [Qwen3-VL](https://ollama.com/library/qwen3-vl) | A vision model, for describing photos | 7.5 |  |

## Part VI — Security

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Frigate](https://frigate.video) | Camera recording and AI object detection | 8.1 |  |
| [Raspberry Pi OS](https://raspberrypi.com/software) | The Raspberry Pis' operating system | 8.4 |  |
| [Suricata](https://suricata.io) | Intrusion detection | 9.2 |  |
| [EveBox](https://evebox.org) | A web interface for Suricata's alerts | 9.2 |  |
| [Kismet](https://kismetwireless.net) | Passive Wi-Fi monitoring | 9.4 |  |

## Part VII — Files, movies and a radio

| Program | What it does in the book | Section | Playbook |
|---|---|---|---|
| [Nextcloud](https://nextcloud.com) | Private file sync | 10.1 |  |
| [Plex](https://plex.tv) | Plays the home movies on every screen | 10.2 |  |
| [OpenWebRX+](https://github.com/luarvique/openwebrx) | A web radio receiver | 10.3 |  |
