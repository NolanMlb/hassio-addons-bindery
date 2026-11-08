# Security

## What the app asks for, and why

| Setting | Value | Justification |
| --- | --- | --- |
| `privileged` | `SYS_ADMIN`, `DAC_READ_SEARCH` | `SYS_ADMIN` is what `mount(2)` requires: mounting the disks a user lists in `localdisks` happens inside the app's own container. `DAC_READ_SEARCH` lets it read files on those disks whose permissions would otherwise deny it (usually written by another app as root). Nothing else is granted. |
| `devices` | `/dev/sd[a-g]`, `/dev/nvme*`, `/dev/mmcblk*`, `/dev/fuse` | Only the nodes a disk can appear as. Without a declared node the container cannot see the disk at all. |
| `udev` | `true` | Mounts the host's udev database read-only, so labels and UUIDs resolve the way they do on the host. |
| `map` | `media:rw`, `share:rw` | The two folders a user can point the library or the downloads at. `homeassistant_config` is **not** mapped: nothing here needs to read your `configuration.yaml`. |
| `host_network` | `false` | The app lives on the Supervisor's bridge network like any other app. |
| `docker_api` | `false` | The app has no reason to touch Docker. |
| `homeassistant_api` | `false` | No Home Assistant API access is requested. |
| `apparmor` | profile provided (`apparmor.txt`) | The profile grants the capability and `mount`/`umount` rules the startup script needs, and confines the rest. |
| `backup` | `cold` | Home Assistant stops the app while taking a snapshot, so the SQLite database is copied consistently. |

If you do not use `localdisks`, `SYS_ADMIN` is never exercised: no mount is attempted. The
capability cannot be made conditional in `config.yaml`, so it is documented here instead.

## Secrets

- **The app stores no credentials.** Prowlarr's API key, qBittorrent's password and every other
  credential live in Bindery's own database, written by Bindery's own interface. There is no second
  copy in the app's options, so there is nothing to leak from `options.json`.
- `env_vars` accepts `!secret name`, resolved by the Supervisor from your `secrets.yaml`: the value
  never appears in the options file or in the app's configuration tab.
- The app log prints the **name** of every `BINDERY_*` variable it exports, and masks values whose
  name contains `PASS`, `TOKEN`, `KEY` or `SECRET`.
- Bindery's backups (in `/data/bindery/backups`) contain credentials in clear text. They are inside
  the app's data folder, included in snapshots — treat a snapshot like the keys it carries, and do
  not attach a backup to an issue.

## Network exposure

- Bindery listens on `8787` inside the container; the Supervisor publishes it on the host. The app
  itself publishes nothing else and does not proxy.
- The app has no internet-facing component. Remote access is your VPN or your reverse proxy; see
  [INSTALL.md](./INSTALL.md#remote-access).
- Bindery validates outbound URLs (SSRF policy, `docs/DEPLOYMENT.md` upstream). Two consequences
  worth knowing: admin-typed service URLs may target the LAN, while indexer-provided download links
  may not target loopback unless `BINDERY_DOWNLOAD_ALLOW_LOOPBACK=true`.

## Files and ownership

- The app runs as root only long enough to mount disks and `chown` its own `/data` folder, then
  drops to `PUID:PGID` with `s6-setuidgid` before starting Bindery.
- It never recursively `chown`s your library or download folders: they may be shared with other apps
  and changing their owner is not this app's decision. It warns when they are not writable by
  `PUID:PGID` instead.
- Folder-only mounts (`sda1/Media/Books`) exist so that a disk holding other data can be exposed
  without the rest of it being reachable.
- Disks are mounted `nosuid,nodev`; FAT/exFAT/NTFS get `uid`/`gid`/`umask=022` rather than the
  `umask=000` (world-writable) some other apps use.

## Data safety rules the app enforces

1. A listed disk that cannot be mounted **stops the app**. A silent start would let Bindery create an
   empty library inside the container and import into it.
2. A library or download path under `/mnt` that is not inside a mount **stops the app**, for the
   same reason.
3. A path outside `/media`, `/share`, `/mnt` and `/data` is accepted with a warning: it will not
   survive a restart, and the log says so.

## Reporting a vulnerability

Open a private security advisory on this repository (Security → Advisories → *Report a
vulnerability*), or a regular issue if the report contains nothing sensitive. Please do not paste
backups, API keys or passwords in an issue.
