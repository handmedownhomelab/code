#!/bin/bash
# proxmox-backup-sync.sh: copy a Proxmox host's backups to a second machine,
# refusing whenever the copy could make things worse.
# Hand-Me-Down Homelab, section 1.4.
#
# Runs on the OTHER machine (the book's GPU tower), nightly, after the
# Proxmox backup job has finished. Install as /usr/local/sbin/proxmox-backup-sync.sh
# (mode 755), and in /etc/cron.d/proxmox-backup-sync:
#   0 3 * * * root /usr/local/sbin/proxmox-backup-sync.sh
# No ">> logfile" on that line: the script is silent when all is well, so
# anything it prints is a problem, and cron mails it to root (playbook 3.3).
#
# Needs: an SSH key on this machine that the Proxmox host accepts for root,
# rsync on both ends, and backups compressed with zstd (*.zst). An
# uncompressed job produces *.tar, which this script doesn't count: it then
# refuses every night ("the source has 0 archives"). Set the job's
# compression to ZSTD.
#
# The guards, in order:
#  1. The source drive must be mounted AND listable. With the book's
#     x-systemd.automount fstab line, `mountpoint -q` passes even when the
#     drive is gone (the automount placeholder is a mount point); it's the
#     `ls` in the same && chain that fails with "No such device". Keep both.
#  2. The source must not have shrunk to less than half the copy. An empty or
#     wrong directory would otherwise make rsync --delete wipe the copy.
#  3. rsync must succeed.
# Tested 2026-10-09 against a nested Proxmox VE 9.2: a normal run, the source
# drive unplugged, and a shrunken source.

PVE=root@192.168.1.20                      # YOUR Proxmox host, by IP address
SSH="ssh -i /root/.ssh/id_ed25519_proxmox -o BatchMode=yes"
SRC=/mnt/usb-backups/dump/                 # the backup storage's dump folder
DEST=/srv/backups/proxmox/dump/            # where the copy lives here

fail() { echo "proxmox-backup-sync refused: $1" >&2; exit 1; }

list=$($SSH "$PVE" "mountpoint -q ${SRC%dump/} && ls $SRC") \
  || fail "can't reach the Proxmox host, or its backup drive isn't mounted"
src=$(grep -c '\.zst$' <<<"$list")
dst=$(ls "$DEST" 2>/dev/null | grep -c '\.zst$')
[ "$src" -gt 0 ] && [ $((src * 2)) -ge "$dst" ] \
  || fail "the source has $src archives, the copy has $dst"
rsync -a --delete -e "$SSH" "$PVE:$SRC" "$DEST" || fail "rsync exited $?"
