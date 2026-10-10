#!/usr/bin/env python3
"""ux7_load_reservations.py — DHCP reservations as code, for a UniFi gateway.

Hand-Me-Down Homelab, section 1.5. Written for a UniFi Express 7 (UX7); it
uses the UniFi OS local API, so other UniFi OS gateways should work too.

Reads a Markdown reservation table (see reservations.example.md), logs into
the gateway's local API, routes each row to a network BY ITS IP ADDRESS, and
creates or updates a MAC-keyed fixed-IP reservation for every device. Run it
twice and the second run does nothing.

BEFORE FIRST USE: edit the "YOUR NETWORK" block below.

SAFETY
  - Default is a DRY RUN. Nothing is written until you pass --apply. That
    goes for every subcommand, --prune included (the book's war story in 1.5
    is what happens when you forget).
  - Credentials never go on the command line. The password is taken from:
      1. the UNIFI_PASS environment variable
      2. the macOS login Keychain, service "unifi-local", account = --username
      3. a prompt
    Store it once in the Keychain (it prompts; nothing lands in shell history):
      security add-generic-password -a <username> -s unifi-local -w
    Pass --no-keychain to skip step 2. On Linux, step 2 simply finds nothing.
  - It needs a LOCAL UniFi admin account. A cloud / SSO account with
    two-factor authentication can't log into the local API.

TYPICAL USE
  ./ux7_load_reservations.py --list              # parse the table, no network
  ./ux7_load_reservations.py                     # dry run: CREATE / UPDATE / SKIP
  ./ux7_load_reservations.py --apply             # write
  ./ux7_load_reservations.py --verify            # read-only config check
  ./ux7_load_reservations.py --prune             # find reservations not in the table
  ./ux7_load_reservations.py --prune --apply     # ...and clear them

THE TABLE
  A Markdown file with a "## Reservations" section holding a three-column
  table: Device | IP | MAC. Only that section is read; parsing stops at the
  next "## " heading, so the same file can hold other tables.

MULTIPLE NETWORKS
  Every row is routed by its own address. MANAGED_CIDRS lists the networks the
  table may contain, and the gateway is asked which of them exist. A row
  outside every managed network fails before anything is written, and so does
  a row for a managed network the gateway doesn't have yet (so a table edited
  ahead of creating a VLAN stops the run instead of landing on the wrong
  network). --network-name forces every row into one named network.

--prune
  Reports every fixed-IP reservation on the gateway whose MAC isn't a live row
  in the table, and with --apply clears it. It CLEARS THE RESERVATION; it
  doesn't delete the client object, so the name and history stay, and re-adding
  the row and re-running --apply restores it exactly.

  Guards, because this is the only path that removes anything:
    - refuses if the table parsed to 0 rows (a parse failure would otherwise
      make everything look orphaned)
    - refuses if orphans exceed PRUNE_SANITY_FRACTION of the reservations,
      the same failure in a subtler form; --force-prune overrides
    - only ever touches objects that have a reservation

--verify
  Read-only. Compares the live gateway against EXPECTED: LAN subnet, gateway
  address, DHCP lease, DHCP pool, DNS servers, the WAN MAC override (if you
  set one), IDS/IPS, and whether every table row has a reservation. Exits 1 on
  any FAIL, so it works from cron. Run it after every firmware update: an
  upgrade can silently reset or rename settings. Anything it can't positively
  confirm prints UNKNOWN rather than PASS, because a check that guesses is
  worse than none.

RETIRED DEVICES
  Rows for hardware you've retired can stay in the table for the record: put
  their MACs in RETIRED_MACS and they're skipped unless --include-retired.
  They then count as orphans for --prune, which is how their old reservations
  get cleared.

License: MIT (see LICENSE).
"""

import argparse
import base64
import getpass
import http.cookiejar
import ipaddress
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

# ==========================================================================
# YOUR NETWORK — edit these. The values are the book's example network.
# ==========================================================================

# Default location of the reservation table.
DEFAULT_INVENTORY = "reservations.md"

# The gateway's address. Override with --host.
DEFAULT_HOST = "192.168.4.1"

# The main LAN. --verify checks ITS settings (gateway, lease, pool, DNS)
# against EXPECTED below.
PRIMARY_LAN_CIDR = ipaddress.ip_network("192.168.4.0/22")

# Every network this loader may write a reservation into. A row whose IP falls
# outside all of them fails before anything is written. Adding a network here
# does NOT create it: the gateway is still the authority on whether it exists,
# and rows for a missing network are refused.
MANAGED_CIDRS = (
    ipaddress.ip_network("192.168.4.0/22"),     # main LAN
    ipaddress.ip_network("192.168.50.0/24"),    # IoT VLAN (section 1.6)
)

# What --verify expects the main LAN to look like.
EXPECTED = {
    "lan_subnet": "192.168.4.0/22",
    "gateway_ip": "192.168.4.1",
    # DHCP's DNS servers, in order: here, the two Pi-holes (section 4.1–4.2).
    "dns": ["192.168.7.173", "192.168.4.26"],
    # 4 hours. Short leases make a DNS or address change reach clients quickly;
    # a 24-hour lease is what made a DNS switch look broken in the book's lab.
    "lease_secs": 14400,
    # If you cloned your old router's WAN MAC to keep the same public IP
    # (section 1.5), put it here and --verify will check it survives firmware
    # updates. None skips the check.
    "wan_mac_override": None,
    # The gateway's own IDS/IPS. False in the book's lab on purpose: it costs
    # throughput, and a separate sensor does the job (Chapter 11). Set it to
    # match your intent; --verify reports whichever you choose.
    "ips_enabled": False,
}

# MACs of retired devices still listed in the table. Skipped unless
# --include-retired; cleared by --prune. Example:
#   "02:00:00:00:00:99",   # old smart plug, replaced 2026-07
RETIRED_MACS = {
}

KEYCHAIN_SERVICE = "unifi-local"

# ==========================================================================


def keychain_password(account):
    """Read the gateway's local-admin password from the macOS login Keychain.

    Returns None if there is no entry, if `security` isn't available (Linux),
    or if the access prompt is denied: all normal, non-fatal outcomes that fall
    through to the prompt.

    The value comes back over a pipe and never touches argv or the
    environment, so it stays out of `ps` and shell history.
    """
    try:
        r = subprocess.run(
            ["security", "find-generic-password",
             "-a", account, "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    pw = r.stdout.strip()
    if pw:
        print(f"Using password from Keychain ({KEYCHAIN_SERVICE}/{account}).")
    return pw or None


MAC_RE = re.compile(r"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$", re.I)


# --------------------------------------------------------------------------
# Inventory parsing
# --------------------------------------------------------------------------
def parse_inventory(path):
    """Return [(name, ip, mac)] from the '## Reservations' table only.

    Stops at the next '## ' heading, so other tables in the same file are
    never picked up.
    """
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()

    rows = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            in_section = line.strip().lower().startswith("## reservations")
            continue
        if not in_section:
            continue
        if not line.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3:
            continue
        name, ip, mac = cells
        # skip header ("Device ... | IP | MAC") and separator ("---|---|---")
        if not MAC_RE.match(mac):
            continue
        try:
            ipaddress.ip_address(ip)
        except ValueError:
            continue
        rows.append((name, ip, mac.lower()))
    return rows


def _managed_cidr_for(ip):
    """Return the MANAGED_CIDRS entry holding `ip`, or None.

    Most-specific first, so an overlapping pair resolves the way a router
    would rather than by declaration order.
    """
    addr = ipaddress.ip_address(ip)
    for net in sorted(MANAGED_CIDRS, key=lambda n: n.prefixlen, reverse=True):
        if addr in net:
            return net
    return None


def preflight(rows):
    """Warn about duplicate IPs/MACs and unmanaged addresses. Returns
    the number of hard problems (outside every managed network, or a
    duplicate IP).

    This is the OFFLINE half of the check -- it answers "is the table allowed
    to contain this address", which --list can ask with no network. Whether
    the controller actually HAS that network is the online half, checked in
    main() once we are logged in.
    """
    problems = 0
    seen_ip, seen_mac = {}, {}
    for name, ip, mac in rows:
        if _managed_cidr_for(ip) is None:
            allowed = ", ".join(str(c) for c in MANAGED_CIDRS)
            print(f"  ! {name} {ip} is OUTSIDE every managed network ({allowed})",
                  file=sys.stderr)
            problems += 1
        if ip in seen_ip:
            print(f"  ! duplicate IP {ip}: {seen_ip[ip]} and {name}", file=sys.stderr)
            problems += 1
        if mac in seen_mac:
            print(f"  ! duplicate MAC {mac}: {seen_mac[mac]} and {name}", file=sys.stderr)
            problems += 1
        seen_ip.setdefault(ip, name)
        seen_mac.setdefault(mac, name)
    return problems


class NetworkMap:
    """Routes a reservation IP to the controller network that should hold it.

    Built from the intersection of MANAGED_CIDRS and what the controller
    actually reports, so `resolve` returning None is a real, actionable
    answer: the address is allowed by policy but the network does not exist
    yet. main() batches those into one refusal rather than 40 write errors.

    `forced` is the --network-name escape hatch: every address resolves to
    that one network, whatever its value.
    """

    def __init__(self, entries, forced=None):
        # most-specific first, so overlapping entries resolve like a router
        self.entries = sorted(entries, key=lambda e: e[0].prefixlen, reverse=True)
        self.forced = forced

    def resolve(self, ip):
        """-> (network_id, name, subnet), or None if no managed network has it."""
        if self.forced:
            return self.forced
        addr = ipaddress.ip_address(ip)
        for net, net_id, name, subnet in self.entries:
            if addr in net:
                return net_id, name, subnet
        return None

    def summary(self):
        """Lines describing what this map will write into."""
        if self.forced:
            net_id, name, subnet = self.forced
            return [f"FORCED  '{name}' {subnet}  (id {net_id})"
                    "  -- every row, regardless of address"]
        lines = [f"        '{name}' {subnet}  (id {net_id})"
                 for _, net_id, name, subnet in self.entries]
        missing = [c for c in MANAGED_CIDRS
                   if not any(net == c for net, _, _, _ in self.entries)]
        for c in missing:
            lines.append(f"        {c} -- MANAGED BUT NOT ON THIS CONTROLLER")
        return lines


# --------------------------------------------------------------------------
# UniFi OS client
# --------------------------------------------------------------------------
def _jwt_csrf(token):
    """Pull the csrfToken claim out of a UniFi OS TOKEN cookie (a JWT)."""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload)).get("csrfToken")
    except Exception:
        return None


class UniFi:
    def __init__(self, host, site, insecure):
        self.base = f"https://{host}"
        self.site = site
        self.csrf = None
        cj = http.cookiejar.CookieJar()
        self.cj = cj
        ctx = ssl.create_default_context()
        if insecure:
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(cj),
            urllib.request.HTTPSHandler(context=ctx),
        )

    def _req(self, method, path, data=None):
        url = self.base + path
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("Content-Type", "application/json")
        if self.csrf:
            req.add_header("X-CSRF-Token", self.csrf)
        try:
            resp = self.opener.open(req, timeout=20)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail}") from None
        except urllib.error.URLError as e:
            raise RuntimeError(f"{method} {path} -> {e.reason}") from None
        # UniFi OS rotates the CSRF token via response header.
        newcsrf = resp.headers.get("X-CSRF-Token") or resp.headers.get(
            "X-Updated-CSRF-Token"
        )
        if newcsrf:
            self.csrf = newcsrf
        raw = resp.read().decode()
        return json.loads(raw) if raw else {}

    def login(self, user, pw):
        self._req("POST", "/api/auth/login", {"username": user, "password": pw})
        if not self.csrf:  # fall back to the JWT claim if no header was sent
            for c in self.cj:
                if c.name == "TOKEN":
                    self.csrf = _jwt_csrf(c.value)
        if not self.csrf:
            raise RuntimeError("login ok but no CSRF token found (check account type)")

    def _net_path(self, tail):
        return f"/proxy/network/api/s/{self.site}/rest/{tail}"

    def find_networks(self, name_override=None):
        """Return a NetworkMap over the managed networks this controller has.

        The controller is the authority twice over: on whether a managed
        network exists at all, and on its network_id, which is what the
        reservation payload actually carries. MANAGED_CIDRS only says which
        ones we are willing to write into.
        """
        data = self._req("GET", self._net_path("networkconf")).get("data", [])

        if name_override:
            for n in data:
                if n.get("name") == name_override:
                    return NetworkMap([], forced=(n["_id"], n.get("name"),
                                                  n.get("ip_subnet") or "?"))
            raise RuntimeError(
                f"no network named {name_override!r} on the controller")

        found = []
        for n in data:
            if n.get("purpose") == "wan":
                continue
            subnet = n.get("ip_subnet") or ""
            if not subnet:
                continue
            try:
                net = ipaddress.ip_interface(subnet).network
            except ValueError:
                continue
            if net in MANAGED_CIDRS:
                found.append((net, n["_id"], n.get("name"), subnet))

        if not found:
            raise RuntimeError(
                "none of the managed networks exist on this controller ("
                + ", ".join(str(c) for c in MANAGED_CIDRS)
                + "); use --network-name to pick one explicitly")
        return NetworkMap(found)

    def users_by_mac(self):
        data = self._req("GET", self._net_path("user")).get("data", [])
        return {u["mac"].lower(): u for u in data if u.get("mac")}

    def networkconf(self):
        return self._req("GET", self._net_path("networkconf")).get("data", [])

    def settings(self):
        return self._req("GET", self._net_path("setting")).get("data", [])

    def upsert(self, existing, name, ip, mac, network_id, apply):
        """Return one of CREATE / UPDATE / SKIP."""
        payload = {
            "mac": mac,
            "name": name,
            "usergroup_id": "",
            "use_fixedip": True,
            "network_id": network_id,
            "fixed_ip": ip,
        }
        cur = existing.get(mac)
        if cur:
            already = (
                cur.get("use_fixedip")
                and cur.get("fixed_ip") == ip
                and cur.get("network_id") == network_id
            )
            if already:
                return "SKIP"
            if apply:
                self._req("PUT", self._net_path(f"user/{cur['_id']}"), payload)
            return "UPDATE"
        if apply:
            self._req("POST", self._net_path("user"), payload)
        return "CREATE"

    def clear_reservation(self, obj, apply):
        """Drop the fixed-IP reservation from an existing client object.

        Deliberately NOT a delete. The object keeps its name, MAC and history;
        only use_fixedip/fixed_ip go away, so re-adding the row to the table
        and re-running --apply restores it exactly. Uses the same PUT path as
        upsert(). REST DELETE on client objects isn't reliably supported (the
        real removal path is cmd/stamgr forget-sta, which is destructive and
        out of scope).
        """
        payload = {
            "mac": obj["mac"],
            "name": obj.get("name") or obj.get("hostname") or obj["mac"],
            "use_fixedip": False,
        }
        if apply:
            self._req("PUT", self._net_path(f"user/{obj['_id']}"), payload)
        return "CLEARED" if apply else "WOULD-CLEAR"


# --------------------------------------------------------------------------
# --verify  (READ-ONLY -- never writes, regardless of --apply)
# --------------------------------------------------------------------------
def _first(d, *keys):
    """Return the first present, non-empty key. UniFi renames fields between
    UniFi OS revisions, so every lookup tries the aliases we have seen."""
    for k in keys:
        v = d.get(k)
        if v not in (None, "", []):
            return v
    return None


def verify(uni, expected_rows):
    """Compare the gateway's live config against EXPECTED. Returns a failure count.

    Deliberately read-only. Anything it cannot positively confirm is reported
    UNKNOWN, not PASS -- a verify that guesses is worse than no verify.
    """
    results = []           # (status, label, actual, expected)
    def add(ok, label, actual, exp):
        results.append(("PASS" if ok else ("UNKNOWN" if ok is None else "FAIL"),
                        label, actual, exp))

    nets = uni.networkconf()
    lan = next((n for n in nets
                if n.get("ip_subnet")
                and _norm_net(n["ip_subnet"]) == str(PRIMARY_LAN_CIDR)), None)
    wan = next((n for n in nets if n.get("purpose") == "wan"), None)

    # --- LAN subnet + gateway -------------------------------------------
    if lan is None:
        add(False, "LAN subnet", "no network matching " + str(PRIMARY_LAN_CIDR),
            EXPECTED["lan_subnet"])
        add(None, "Gateway IP", "(LAN not found)", EXPECTED["gateway_ip"])
        add(None, "DHCP lease", "(LAN not found)", f'{EXPECTED["lease_secs"]}s')
        add(None, "DHCP pool", "(LAN not found)", "explicit range")
        add(None, "DNS servers", "(LAN not found)", ", ".join(EXPECTED["dns"]))
    else:
        add(_norm_net(lan["ip_subnet"]) == EXPECTED["lan_subnet"],
            "LAN subnet", _norm_net(lan["ip_subnet"]), EXPECTED["lan_subnet"])

        gw = str(ipaddress.ip_interface(lan["ip_subnet"]).ip)
        add(gw == EXPECTED["gateway_ip"], "Gateway IP", gw,
            EXPECTED["gateway_ip"])

        lease = _first(lan, "dhcpd_leasetime")
        if lease is None:
            add(None, "DHCP lease", "not reported", f'{EXPECTED["lease_secs"]}s')
        else:
            add(int(lease) == EXPECTED["lease_secs"], "DHCP lease",
                f"{lease}s ({int(lease)//3600}h)",
                f'{EXPECTED["lease_secs"]}s ({EXPECTED["lease_secs"]//3600}h)')

        start, stop = _first(lan, "dhcpd_start"), _first(lan, "dhcpd_stop")
        add(bool(start and stop), "DHCP pool",
            f"{start} - {stop}" if start and stop else "not set",
            "explicit range (UniFi will not auto-size a /22)")

        dns = [v for v in (_first(lan, "dhcpd_dns_1"), _first(lan, "dhcpd_dns_2"),
                           _first(lan, "dhcpd_dns_3"), _first(lan, "dhcpd_dns_4"))
               if v]
        add(dns == EXPECTED["dns"], "DNS servers",
            ", ".join(dns) if dns else "none set (gateway/auto)",
            ", ".join(EXPECTED["dns"]))

    # --- WAN MAC override ------------------------------------------------
    if EXPECTED.get("wan_mac_override") is None:
        pass    # not configured: nothing to check
    elif wan is None:
        add(None, "WAN MAC override", "no WAN network found",
            EXPECTED["wan_mac_override"])
    else:
        mac = _first(wan, "mac_override", "wan_mac_override", "macOverride")
        if mac is None:
            add(False, "WAN MAC override", "not set", EXPECTED["wan_mac_override"])
        else:
            add(mac.lower() == EXPECTED["wan_mac_override"].lower(),
                "WAN MAC override", mac.lower(), EXPECTED["wan_mac_override"])

    # --- IDS/IPS ---------------------------------------------------------
    # Checked against EXPECTED["ips_enabled"], NOT hard-coded to "should be on".
    # A check that reports FAIL on a deliberate, correct configuration gets
    # ignored, which is worse than not checking.
    want_ips = EXPECTED.get("ips_enabled", False)
    exp_txt = ("enabled — 'ids' (detect) or 'ips' (detect+block)" if want_ips
               else "disabled — by design (EXPECTED['ips_enabled'] is False)")
    ips = next((s for s in uni.settings() if s.get("key") == "ips"), None)
    if ips is None:
        add(None, "IDS/IPS", "no 'ips' setting object returned", exp_txt)
    else:
        mode = _first(ips, "ips_mode", "mode") or "unknown"
        if mode == "unknown":
            add(None, "IDS/IPS", "mode=unknown (field not recognised)", exp_txt)
        else:
            on = mode != "disabled" or bool(ips.get("enabled"))
            add(on == want_ips, "IDS/IPS", f"mode={mode}", exp_txt)

    # --- reservations ----------------------------------------------------
    existing = uni.users_by_mac()
    fixed = {m: u for m, u in existing.items() if u.get("use_fixedip")}
    want = {m for _, _, m in expected_rows}
    missing = want - set(fixed)
    add(not missing, "Reservations",
        f"{len(fixed)} fixed-IP objects on the gateway"
        + (f"; {len(missing)} from the inventory MISSING" if missing else ""),
        f"{len(want)} (all live rows in the table)")

    # --- report ----------------------------------------------------------
    width = max(len(r[1]) for r in results)
    print("\n=== VERIFY (read-only) ===")
    for status, label, actual, exp in results:
        mark = {"PASS": "ok  ", "FAIL": "FAIL", "UNKNOWN": "??  "}[status]
        print(f"  {mark} {label:<{width}}  {actual}")
        if status != "PASS":
            print(f"       {'':<{width}}  expected: {exp}")

    fails = sum(1 for r in results if r[0] == "FAIL")
    unknown = sum(1 for r in results if r[0] == "UNKNOWN")
    print(f"\n  {len(results)-fails-unknown} pass, {fails} fail, {unknown} unknown")
    if unknown:
        print("  UNKNOWN = this UniFi OS revision did not return a field we know.\n"
              "  Check it by hand in the UI and, if the field moved, teach _first().")
    if missing:
        print(f"\n  Missing reservations ({len(missing)}): re-run without --verify"
              " to see them, then --apply.")
    return fails


# --------------------------------------------------------------------------
# --prune  (the only path that removes anything; dry run unless --apply)
# --------------------------------------------------------------------------
# Refuse to prune if more than this fraction of the gateway's fixed-IP objects
# look orphaned. A healthy reconcile touches a handful; a large fraction means
# the table was misparsed or pointed at the wrong file, and the guard turns a
# silent mass-clear into a stop. Override with --force-prune once you have
# looked at the dry run and believe it.
PRUNE_SANITY_FRACTION = 0.25


def prune(uni, rows, apply, force):
    """Clear fixed-IP reservations on the gateway that are not live table rows.

    Returns an exit code: 0 nothing to do or done, 2 refused by a guard,
    1 one or more writes failed.
    """
    existing = uni.users_by_mac()
    fixed = {m: u for m, u in existing.items() if u.get("use_fixedip")}
    want = {m for _, _, m in rows}
    orphans = {m: u for m, u in fixed.items() if m not in want}

    print("\n=== PRUNE ===")
    print(f"  table (live rows)     : {len(want)}")
    print(f"  gateway fixed-IP objs : {len(fixed)}")
    print(f"  orphaned on gateway   : {len(orphans)}")

    # Guard 1: a parse break makes every object look orphaned.
    if not want:
        print("\n  REFUSING: the inventory parsed to 0 rows. That is a parse\n"
              "  failure, not an empty table -- every reservation would look\n"
              "  orphaned. Check --inventory and the '## Reservations' heading.",
              file=sys.stderr)
        return 2

    if not orphans:
        print("\n  Nothing to prune -- the gateway matches the table.")
        return 0

    # Guard 2: the same failure, subtler. Proportion, not count.
    frac = len(orphans) / len(fixed) if fixed else 0
    if frac > PRUNE_SANITY_FRACTION and not force:
        print(f"\n  REFUSING: {len(orphans)} of {len(fixed)} fixed-IP objects "
              f"({frac:.0%}) look orphaned,\n"
              f"  over the {PRUNE_SANITY_FRACTION:.0%} sanity limit. That usually means the "
              "table was\n  misparsed or --inventory points somewhere unexpected, not that "
              "the\n  gateway really drifted this far. Review the list below, then pass\n"
              "  --force-prune if it is genuinely correct.", file=sys.stderr)
        for mac, u in sorted(orphans.items(), key=_orphan_sort):
            print(f"    {_orphan_label(mac, u)}", file=sys.stderr)
        return 2

    mode = "APPLY" if apply else "DRY RUN"
    print(f"\n  {mode} -- clearing use_fixedip (client objects are kept):")
    failed = 0
    for mac, u in sorted(orphans.items(), key=_orphan_sort):
        label = _orphan_label(mac, u)
        try:
            action = uni.clear_reservation(u, apply)
        except RuntimeError as e:
            failed += 1
            print(f"    ERROR        {label}: {e}", file=sys.stderr)
        else:
            print(f"    {action:<12} {label}")

    if not apply:
        print("\n  Nothing was written. Re-run with --apply to commit.")
    elif not failed:
        print(f"\n  Cleared {len(orphans)} reservation(s). The client objects "
              "remain;\n  re-add the row and --apply to restore any of them.")
    if failed:
        print(f"\n  {failed} write(s) failed -- see above.", file=sys.stderr)
        return 1
    return 0


def _orphan_sort(item):
    """Sort orphans by reserved IP, tolerating a missing/blank fixed_ip."""
    try:
        return (0, ipaddress.ip_address(item[1].get("fixed_ip")))
    except (ValueError, TypeError):
        return (1, item[0])


def _orphan_label(mac, u):
    """'<ip> <mac>  <name>' for one orphan, safe against null/absent fields.

    Note .get('fixed_ip', '?') is NOT enough: UniFi returns the key with a
    null value for objects that lost their reservation, and dict.get only
    substitutes the default when the key is absent -- so the '?' never fires
    and f-string formatting raises TypeError on None.
    """
    ip = u.get("fixed_ip") or "?"
    name = u.get("name") or u.get("hostname") or ""
    return f"{ip:<15} {mac}  {name}"


def _norm_net(ip_subnet):
    """'192.168.4.1/22' -> '192.168.4.0/22' (UniFi stores the gateway IP here)."""
    try:
        return str(ipaddress.ip_interface(ip_subnet).network)
    except ValueError:
        return ip_subnet


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="Bulk-load DHCP reservations onto a UniFi gateway."
    )
    ap.add_argument("--host", default=DEFAULT_HOST,
                    help=f"gateway address (default: {DEFAULT_HOST})")
    ap.add_argument("--site", default="default", help="UniFi site (default: default)")
    ap.add_argument("--inventory", default=DEFAULT_INVENTORY,
                    help=f"path to the reservation table (default: {DEFAULT_INVENTORY})")
    ap.add_argument("--username", default=os.environ.get("UNIFI_USER"),
                    help="UniFi local admin (or env UNIFI_USER)")
    ap.add_argument("--no-keychain", action="store_true",
                    help=f"skip the login Keychain ({KEYCHAIN_SERVICE}) and prompt instead")
    ap.add_argument("--network-name",
                    help="ESCAPE HATCH: force EVERY row into the network with "
                         "this name, ignoring per-row address routing")
    ap.add_argument("--apply", action="store_true",
                    help="actually write (default is a dry run)")
    ap.add_argument("--include-retired", action="store_true",
                    help="also load the known-retired devices")
    ap.add_argument("--verify-tls", action="store_true",
                    help="verify the gateway's certificate (off by default; it is self-signed)")
    ap.add_argument("--list", action="store_true",
                    help="just parse and print the inventory, then exit (no network)")
    ap.add_argument("--verify", action="store_true",
                    help="READ-ONLY: check the gateway's live config against EXPECTED "
                         "(subnet, gateway, lease, pool, DNS, WAN MAC, IDS/IPS, "
                         "reservation count) and exit. Never writes.")
    ap.add_argument("--prune", action="store_true",
                    help="clear fixed-IP reservations on the gateway that are no longer "
                         "live rows in the table (retired MACs included). Dry run "
                         "unless --apply. Clears use_fixedip; keeps the client object.")
    # argparse %-formats help strings, so a literal '%' has to be doubled -- and
    # the doubling must happen after formatting ('.0%%' is not a valid spec).
    pct = f"{PRUNE_SANITY_FRACTION:.0%}".replace("%", "%%")
    ap.add_argument("--force-prune", action="store_true",
                    help=f"let --prune exceed the {pct} orphan "
                         "sanity limit (review the dry run first)")
    args = ap.parse_args()

    if args.prune and args.verify:
        ap.error("--prune and --verify are mutually exclusive "
                 "(--verify is read-only by contract; run it first, then --prune)")
    if args.force_prune and not args.prune:
        ap.error("--force-prune only means anything with --prune")

    rows = parse_inventory(args.inventory)
    if not args.include_retired:
        kept = [r for r in rows if r[2] not in RETIRED_MACS]
        skipped = len(rows) - len(kept)
        rows = kept
    else:
        skipped = 0

    print(f"Parsed {len(rows)} reservations from {args.inventory}"
          + (f" ({skipped} retired skipped)" if skipped else ""))
    problems = preflight(rows)

    if args.list:
        for name, ip, mac in sorted(rows, key=lambda r: ipaddress.ip_address(r[1])):
            print(f"  {ip:<15} {mac}  {name}")
        if problems:
            print(f"\n{problems} preflight problem(s) -- see above", file=sys.stderr)
        return

    if problems:
        print(f"\nRefusing to continue: {problems} preflight problem(s) above.",
              file=sys.stderr)
        sys.exit(2)

    user = args.username or input("UniFi username: ")
    pw = (os.environ.get("UNIFI_PASS")
          or (None if args.no_keychain else keychain_password(user))
          or getpass.getpass("UniFi password: "))

    uni = UniFi(args.host, args.site, insecure=not args.verify_tls)
    print(f"\nLogging in to {uni.base} ...")
    uni.login(user, pw)

    if args.verify:
        sys.exit(1 if verify(uni, rows) else 0)

    if args.prune:
        sys.exit(prune(uni, rows, args.apply, args.force_prune))

    netmap = uni.find_networks(args.network_name)
    print("Target networks:")
    for line in netmap.summary():
        print(line)

    # Online half of preflight. A row can be inside a MANAGED_CIDR and still
    # have nowhere to go, if that network hasn't been created on the gateway
    # yet. Refuse the whole run rather than write some of it.
    unresolved = [(n, i, m) for n, i, m in rows if netmap.resolve(i) is None]
    if unresolved:
        print(f"\nRefusing to continue: {len(unresolved)} row(s) target a "
              "managed network that does not exist on this controller.",
              file=sys.stderr)
        for name, ip, mac in sorted(unresolved,
                                    key=lambda r: ipaddress.ip_address(r[1])):
            cidr = _managed_cidr_for(ip)
            print(f"  ! {ip:<15} {mac}  {name}  (wants {cidr})", file=sys.stderr)
        print("\nCreate the network first, or use --network-name to override.",
              file=sys.stderr)
        sys.exit(2)

    existing = uni.users_by_mac()
    print(f"Existing client objects: {len(existing)}")

    mode = "APPLY" if args.apply else "DRY RUN"
    print(f"\n=== {mode} ===")
    tally = {"CREATE": 0, "UPDATE": 0, "SKIP": 0, "ERROR": 0}
    per_net = {}
    for name, ip, mac in sorted(rows, key=lambda r: ipaddress.ip_address(r[1])):
        net_id, net_name, _ = netmap.resolve(ip)
        try:
            action = uni.upsert(existing, name, ip, mac, net_id, args.apply)
        except RuntimeError as e:
            action = "ERROR"
            print(f"  ERROR  {ip:<15} {mac}  {name}: {e}", file=sys.stderr)
        else:
            print(f"  {action:<6} {ip:<15} {mac}  {name}  [{net_name}]")
        tally[action] += 1
        per_net.setdefault(net_name, {"CREATE": 0, "UPDATE": 0,
                                      "SKIP": 0, "ERROR": 0})[action] += 1

    print(f"\n{mode} summary: " +
          ", ".join(f"{k}={v}" for k, v in tally.items()))
    if len(per_net) > 1:
        for net_name in sorted(per_net):
            print(f"  {net_name:<12} " +
                  ", ".join(f"{k}={v}" for k, v in per_net[net_name].items()))
    if not args.apply:
        print("Nothing was written. Re-run with --apply to commit.")
    if tally["ERROR"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
