#!/bin/bash
# Apply the settings custom.toml would have set, on a Pi that was already
# flashed and booted without it (e.g. set up through Raspberry Pi Imager).
#
# Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
# Run once: sudo speedcam-apply-firstboot-settings.sh
#
# Deliberately does NOT set the hostname: the name typed into Raspberry Pi
# Imager wins. Renaming a running headless host breaks mDNS, the DHCP
# reservation and any open session for no benefit.
#
# Deliberately does NOT touch the Wi-Fi connection. It is already associated
# and this is a headless host; rewriting wpa/NM config to set
# an SSID it already has is pure downside risk.

set -uo pipefail   # NOT -e: every step is individually tolerant on purpose

# ---- settings: YOURS, not the book's -------------------------------------
TZ_NAME="${SPEEDCAM_TZ:-America/New_York}"   # every CSV row is stamped in it
LOCALE="${SPEEDCAM_LOCALE:-en_US.UTF-8}"
KEYMAP="${SPEEDCAM_KEYMAP:-us}"
WIFI_COUNTRY="${SPEEDCAM_WIFI_COUNTRY:-US}"
# -------------------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

step() { printf '\n=== %s\n' "$*"; }

step "Timezone"
if [ "$(timedatectl show -p Timezone --value)" = "$TZ_NAME" ]; then
    echo "  already $TZ_NAME - no change"
else
    timedatectl set-timezone "$TZ_NAME" && echo "  set to $TZ_NAME"
fi
echo "  NOTE: every CSV row is stamped in this zone by speedcam_export.py."

step "Locale -> $LOCALE"
if locale | grep -q "$LOCALE"; then
    echo "  already $LOCALE"
else
    raspi-config nonint do_change_locale "$LOCALE" \
        && echo "  set (takes effect on next login)" \
        || echo "  WARN: raspi-config locale step failed - non-fatal"
fi

step "Console keymap -> $KEYMAP"
raspi-config nonint do_configure_keyboard "$KEYMAP" \
    && echo "  set" \
    || echo "  WARN: keymap step failed - non-fatal (headless, cosmetic)"

step "Wi-Fi regulatory domain -> $WIFI_COUNTRY"
# Channel/power compliance only. Does not re-associate.
raspi-config nonint do_wifi_country "$WIFI_COUNTRY" \
    && echo "  set" \
    || echo "  WARN: wifi country step failed - non-fatal"

step "SSH: disable password authentication"
# NOTE THE 01- PREFIX. sshd uses FIRST-OBTAINED-VALUE-WINS, and Raspberry Pi OS
# ships /etc/ssh/sshd_config.d/50-cloud-init.conf containing
# "PasswordAuthentication yes". A 99- drop-in is read AFTER it and is therefore
# ignored - which is exactly what happened on the author's Pi on 2026-09-09: the file
# was installed, sshd reloaded cleanly, and password auth stayed on.
# 50-cloud-init.conf is mode 0600 root-only, so a non-root grep of it returns
# nothing and reads like "no password lines" rather than "cannot read".
DROPIN=/etc/ssh/sshd_config.d/01-speedcam.conf
LEGACY=/etc/ssh/sshd_config.d/99-speedcam.conf
if [ ! -d /etc/ssh/sshd_config.d ]; then
    echo "  WARN: no sshd_config.d on this image - skipping rather than editing sshd_config"
else
    [ -f "$LEGACY" ] && { rm -f "$LEGACY"; echo "  removed ineffective $LEGACY"; }
    cat > "$DROPIN" <<'CONF'
# speedcam hardening - key-only SSH. Remove this file and reload sshd to revert.
# Must sort BEFORE 50-cloud-init.conf: sshd takes the first value it sees.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
CONF
    chmod 644 "$DROPIN"
    if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
        # Verify the EFFECTIVE value, and fail loudly if it did not take.
        # The previous version printed this readback and then declared success
        # regardless of what it said.
        EFF=$(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')
        if [ "$EFF" = "no" ]; then
            echo "  OK - password auth disabled (effective: $EFF)"
        else
            echo "  ERROR: drop-in installed but effective passwordauthentication=$EFF" >&2
            echo "         Something earlier in sshd_config.d is winning. Check:" >&2
            echo "           sudo sshd -T | grep -i passwordauth" >&2
            echo "           sudo grep -ri passwordauth /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config" >&2
        fi
    else
        rm -f "$DROPIN"
        echo "  ERROR: sshd -t rejected the config; drop-in removed, nothing changed" >&2
    fi
fi

step "Result"
timedatectl | sed 's/^/  /'
echo
echo "  hostname left as: $(hostname)   (intentional - see header)"
echo "  SSH password auth: $(sshd -T 2>/dev/null | awk "/^passwordauthentication/{print \$2}")"
