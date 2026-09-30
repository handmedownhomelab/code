# Reservations (example)

Invented devices and addresses: replace them with your own. The MACs use the
`02:` prefix, which marks an address as locally administered, so none of them
belongs to real hardware.

Only the table under `## Reservations` is read. Leave UniFi's own switches
and access points out: the controller owns their addresses and the gateway
refuses a reservation for them (`FixedIpAlreadyUsedByDevice`).

## Reservations

| Device | IP | MAC |
|---|---|---|
| proxmox | 10.20.3.208 | 02:00:00:00:00:01 |
| pihole | 10.20.3.173 | 02:00:00:00:00:02 |
| ha | 10.20.3.172 | 02:00:00:00:00:03 |
| pihole2 | 10.20.0.26 | 02:00:00:00:00:04 |
| gpu-tower | 10.20.3.140 | 02:00:00:00:00:05 |
| smart-plug-kitchen | 10.20.50.20 | 02:00:00:00:00:06 |

## Not reserved

Anything under another heading is ignored, so notes like this can live in
the same file.
