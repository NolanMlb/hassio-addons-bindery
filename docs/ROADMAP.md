# Roadmap

Deliberately not implemented yet, with the reason, so that the missing pieces are decisions rather
than gaps.

## Ingress (Bindery inside the Home Assistant sidebar)

Bindery supports a URL prefix (`BINDERY_URL_BASE`), so ingress looks feasible. It was left out
because ingress also changes cookie scope, absolute redirects and the first-run `/setup` flow, and
none of that could be verified on a real Supervisor here. A half-working ingress — a blank panel in
the sidebar — is worse than a working port.

What a contribution would need: set `BINDERY_URL_BASE` from the ingress URL the Supervisor exposes,
set `ingress: true` and `ingress_port: 8787`, verify the setup wizard, login, OPDS links and file
downloads behind the prefix, and add a `connection_mode`-style switch for users who prefer the port.

## Network shares (CIFS/NFS)

Today storage is: Home Assistant folders, or a local disk. A share is a third failure model
(availability, credentials, timeouts, stale handles) and Bindery's own documentation warns that
network filesystems can change client IDs. It would need its own options (`cifsusername`,
`cifspassword`, `networkdisks`) and a health check that does not hang the startup.

## Configurable container port

`BINDERY_PORT` is fixed at 8787 because the Supervisor maps that port, the *Open Web UI* button and
the health check point at it. The host-side port is already changeable in the app's **Network**
settings. A separate option would let users pick a port that nothing else knows about.

## Automatic upstream tracking

A scheduled workflow could notice a new Bindery release, bump `BINDERY_VERSION`, bump `version`,
write the changelog entry and open a PR. It is not wired because a release pipeline that publishes
without review is a liability; Renovate already opens the version bump as a PR.

## More device names

`devices:` is static in `config.yaml`, so a disk that shows up as `/dev/sdh1` or `/dev/nvme3n1p1` is
not visible. Adding names costs nothing but lengthens the list; the real fix is upstream support for
a user-editable device list, which does not exist today. Open an issue and the node will be added.

## Per-app Armor profile hardening

`apparmor.txt` grants `file,` (all file access) because the library can be anywhere, and the
capability/`mount` rules the startup script needs. A tighter profile is possible with per-path
rules, but it has to be developed against a running instance with `apparmor_parser` complaints,
which is best done by someone with the hardware in front of them.
