# Technical audit

What this app is built on. Every claim below was checked against the sources named next to it —
the point of writing it down is that nothing here is guessed, and anything Bindery does not support
is not implemented.

Audit date: 2026-11-08. Bindery `v1.48.0` (latest release), container image
`ghcr.io/vavallee/bindery:1.48.0`.

## 1. The application

- **Bindery** — https://github.com/vavallee/bindery, MIT, written in Go with an embedded web UI
  (`go:embed`). Automated ebook and audiobook manager; monitors authors, searches indexers,
  downloads through a download client, imports and renames into a library.
- Supported download clients: qBittorrent, SABnzbd, Transmission, Deluge, rTorrent, NZBGet
  (`docs/DEPLOYMENT.md`). Indexers can be configured directly or synchronised from Prowlarr
  (`POST /api/v1/prowlarr/{id}/sync`, `docs/API.md`).
- There is **no Readarr-style "root folder per library" REST surface to seed from outside**: root
  folders live in the database and are created in the interface. This app therefore never tries to
  pre-create one.

## 2. The container image

Source: `Dockerfile` in the repository, and `docker buildx imagetools inspect` run against the
published image.

| Fact | Value | Consequence for the app |
| --- | --- | --- |
| Registry | `ghcr.io/vavallee/bindery`, mirrored as `vavallee/bindery` on Docker Hub | We consume `ghcr.io`, the canonical one |
| Architectures | `linux/amd64` and `linux/arm64` only (multi-arch manifest, verified) | `arch: [aarch64, amd64]`, nothing else |
| Base | `gcr.io/distroless/static-debian13:nonroot` | No shell, no `gosu`, no runtime user switching |
| User | `nonroot`, UID/GID 65532, set with `USER nonroot` | We cannot `chown` from inside it; the app image adds its own root entrypoint |
| Port | `EXPOSE 8787`, `BINDERY_PORT` defaults to 8787 | Fixed inside the container, mapped by the Supervisor |
| Entrypoint | `/bindery`, statically linked (`CGO_ENABLED=0`) | Copying the file into another image is safe |
| Health | `HEALTHCHECK` runs `/bindery healthcheck`, which calls `GET /api/v1/health` | Same endpoint used by the app's own health check |
| Licence files | `/LICENSE`, `/THIRD_PARTY_LICENSES.md` | Copied into our image, as redistribution requires |
| Tags | `latest`, `X.Y.Z`, `vX.Y.Z`, `edge`, `development`, `sha-<hash>` | We pin `X.Y.Z` |

`armv7` exists **for the release binaries**, not for the container image (the release page lists
`linux_armv7` archives). Declaring `armv7` in `config.yaml` would mean building and maintaining our
own Bindery image for 32-bit ARM, which contradicts "use the official image and do not fork".
Decision: `aarch64` and `amd64` only, and the documentation says why.

## 3. Volumes and directories

From `docs/DEPLOYMENT.md` (Docker section) and the environment table:

| Path | Default | Overridable with |
| --- | --- | --- |
| `/config` | database and data directory | `BINDERY_DB_PATH`, `BINDERY_DATA_DIR` |
| `/books` | ebook library | `BINDERY_LIBRARY_DIR` |
| `/downloads` | completed downloads | `BINDERY_DOWNLOAD_DIR` |
| `/audiobooks` | audiobook library (falls back to `/books`) | `BINDERY_AUDIOBOOK_DIR` |

Because every one of these is overridable, the app does **not** bind-mount anything at
`/books` or `/downloads`: it points Bindery at whatever path the user configured, and only mounts
Home Assistant's folders and the disks the user asks for.

`/config` is deliberately not used for Bindery's data. In a Home Assistant app the config folder
(`/config`, mapped to `/homeassistant` by the Supervisor) belongs to Home Assistant, and the app's
own persistent folder is `/data`. Bindery's data therefore goes to `/data/bindery`, which survives
restarts and updates and is included in snapshots.

## 4. Environment variables

Only variables documented in `docs/DEPLOYMENT.md` are used. The full documented set is much larger;
these are the ones the app drives:

| Variable | Driven by | Why |
| --- | --- | --- |
| `BINDERY_DATA_DIR`, `BINDERY_DB_PATH` | fixed to `/data/bindery` | persistence |
| `BINDERY_LIBRARY_DIR`, `BINDERY_DOWNLOAD_DIR` | `library_dir`, `downloads_dir` | storage |
| `BINDERY_AUDIOBOOK_DIR`, `BINDERY_AUDIOBOOK_DOWNLOAD_DIR` | `audiobooks_dir`, `audiobook_downloads_dir` (only exported when set) | separate audiobook storage |
| `BINDERY_PORT` | fixed to 8787 | the Supervisor's port mapping and health check |
| `BINDERY_LOG_LEVEL` | `log_level` | log verbosity |
| `BINDERY_DIR_MODE` | `dir_mode` | permissions of created folders |
| `BINDERY_TELEMETRY_DISABLED` | inverse of `telemetry` | opt out from the first start |
| `BINDERY_PUID`, `BINDERY_PGID` | `PUID`, `PGID` | see below |
| any other `BINDERY_*` | `env_vars` | advanced knobs, user's choice |

### `PUID` / `PGID` are assertions, not a user switch

Quoted from the documentation: *"`BINDERY_PUID` / `BINDERY_PGID` are **sanity checks, not user
switchers.** […] If you set them but forget the `--user` side, Bindery fails fast at startup."*
The distroless image has no `gosu`, so it cannot change user itself.

The app therefore runs its own root entrypoint, drops privileges with `s6-setuidgid` to `PUID:PGID`,
and *then* exports `BINDERY_PUID`/`BINDERY_PGID` with exactly those values, so the upstream check
passes on a correct start and fails loudly if our own logic ever regresses. Verified: the log line
`PUID/PGID match confirmed` appears with `PUID=1000`.

## 5. Hardlinks: the constraint that shapes the storage design

From `docs/DEPLOYMENT.md`, *"Storage layout and hardlinks (single mount)"*:

> Bindery imports in `auto` mode by default: it hardlinks when the completed download and the
> library destination are on the **same filesystem**, and copies otherwise. […] Two separate bind
> mounts get different device IDs even when they point at the same host filesystem.

Consequences, all implemented:

1. The default layout puts both folders under `/media` (one mount): hardlinks by default.
2. The app checks `stat -c %d` for both folders at startup and warns when they are on different
   filesystems, instead of letting the user discover a doubled disk usage weeks later.
3. The documentation recommends mounting a whole disk (`sda1`) rather than two folders of it when
   hardlinks matter.

## 6. `localdisks` in AlexBELGIUM's apps: what it actually is

Read from `alexbelgium/hassio-addons` (`.templates/00-local_mounts.sh`, his apps' `config.yaml`).

- It is **not** a Supervisor feature. The Supervisor only bind-mounts the folders declared in
  `map`; there is no option to mount an arbitrary host path.
- His apps declare `devices:` (a list of `/dev/...` nodes) and
  `privileged: [SYS_ADMIN, DAC_READ_SEARCH]` in `config.yaml`, then run a `cont-init` script that
  calls `mount` **inside the container's own mount namespace**. The mount is therefore visible to
  that app only — the host and the other apps never see `/mnt/sda1`.
- He depends on his own `bashio` templates and on his base images being able to `chown` and to run
  `mount` as root.
- Supported filesystems come from `/proc/filesystems` at runtime; `vfat`/`exfat`/`ntfs` get
  `umask=000`, everything else is mounted with `nosuid,relatime,noexec`.

This app reimplements the same idea from scratch (≈150 lines of Bash, no shared template, no
dependency on his images), with these deliberate differences:

| AlexBELGIUM | This app | Why |
| --- | --- | --- |
| `umask=000` on FAT/NTFS | `uid=PUID,gid=PGID,umask=022` | files end up owned by the app's user instead of world-writable |
| mounts `nosuid,nodev,noexec` | `nosuid,nodev` | `noexec` breaks nothing today, but has no benefit here either; `nodev` covers the real risk |
| a failed mount stops the app | same | a missing disk must never look like an empty library |
| legacy `/share/<disk>` fallback | removed | the app is new; no compatibility to preserve |
| label/UUID lookup via `lsblk | grep` | `blkid` parsing, plus a warning when a label matches several disks | `grep` on `lsblk` output matches substrings |
| `bashio` for everything | plain Bash + `jq`, `bashio` not required | the same scripts run outside Home Assistant, which is what the test suite does |

## 7. Home Assistant mechanics used

From the current app documentation (`contributors.home-assistant.io/apps/reference/configuration/`):

- `map` with typed entries (`media`, `share`) → `/media`, `/share`, read-write.
- `devices` → the device nodes the container may see.
- `privileged: [SYS_ADMIN, DAC_READ_SEARCH]` → the capabilities `mount` needs.
- `udev: true` → `/run/udev`, so device enumeration works the way it does on the host.
- `image` without a tag + `version` → the Supervisor pulls `image:version`, which is why the app
  version is part of the release process.
- `webui` with `[HOST]`/`[PORT:8787]` → the *Open Web UI* button points at the mapped port, not at a
  user-configurable one. Health comes from the image's `HEALTHCHECK` on `/api/v1/health` (the store linter
  now treats the `watchdog` key as obsolete in favour of that).
- `backup: cold` → the container is stopped during a snapshot, so the SQLite database is copied
  consistently. A hot copy of a WAL database can be torn.
- `init: false` → the S6 overlay of the base image is PID 1.
- `options`/`schema` → the form in the interface; `!secret` is resolved by the Supervisor, so a
  user can reference `secrets.yaml` in `env_vars` without the app knowing about it.

## 8. What was *not* implemented, and why

| Feature | Status | Reason |
| --- | --- | --- |
| Ingress (interface inside the Home Assistant sidebar) | not implemented | Bindery supports a URL prefix (`BINDERY_URL_BASE`), but ingress also changes how cookies, redirects and the setup flow behave, and this was not verified on a real Supervisor. A half-working ingress would be worse than none: the app uses the standard port mapping instead. |
| In-app Prowlarr/qBittorrent settings | not implemented | Bindery has no environment variables for them (verified: no `PROWLARR_*`/`QBITTORRENT_*` in the sources). They are configured in Bindery, in its UI or through its API. Duplicating the credentials in the app options would create a second, silently stale source of truth. |
| `armv7` / `armhf` | not supported | No upstream container image for those architectures. Supporting them means maintaining a forked image. |
| Network shares (CIFS/NFS) as storage | not implemented | Not required to run Bindery, and a network share is a different failure model (availability, timeouts) than a local disk. Tracked in the roadmap. |
| Automatic Bindery upgrades inside the app | not applicable | Upgrading means publishing a new app image with a new `BINDERY_VERSION`; users update from the store. |

## 9. Version policy

`version` in `config.yaml` is `<Bindery version>-<app revision>`, e.g. `1.48.0-1`. It is both the
tag the Supervisor pulls and what users see in the store, so a Bindery release and an app fix are
distinguishable at a glance. `latest` is published for convenience but the manifest Home Assistant
pulls is pinned by `version`.
