# Home Assistant App: Bindery

Bindery is an automated ebook and audiobook manager: you add authors or books, it searches your
indexers (directly or through Prowlarr), sends the release to a download client (qBittorrent,
SABnzbd, Transmission, Deluge, rTorrent, NZBGet), then renames and files what it downloaded into
your library.

This app runs the official Bindery image inside Home Assistant and turns everything that depends
on *your* installation — folders, disks, ownership, timezone — into options you edit in the Home
Assistant interface. Bindery's own interface is then opened from the app page.

## Install

1. **Settings → Apps → App store** (older versions: *Add-on store*).
2. Three-dot menu → **Repositories**, add `https://github.com/NolanMlb/hassio-addons-bindery`.
3. Install **Bindery**, then **Start** it. It works immediately with the defaults: the library
   lands in `/media/books`, the download folder is `/media/downloads`.
4. Open the web interface and create the admin account. Bindery asks for a password on the first
   visit and nothing else.

Nothing else is mandatory. No external disk, no Prowlarr, no download client is required to start
the app; those are configured afterwards, in Bindery.

## Options

### General

| Option | Default | Meaning |
| --- | --- | --- |
| `log_level` | `info` | `debug`, `info`, `warn` or `error`. `debug` when you report a problem. |
| `TZ` | `UTC` | Timezone of the container, e.g. `Europe/Paris`. Set it: it dates the log entries and Bindery's scheduled jobs. |
| `PUID` / `PGID` | `0` / `0` | Owner of the files Bindery writes. `0` is root, which matches the default of most download clients in Home Assistant. |
| `telemetry` | `true` | Bindery sends one anonymous ping a day. Turn it off here to disable it from the first start. |
| `env_vars` | `[]` | Advanced: any `BINDERY_*` variable from [Bindery's documentation](https://github.com/vavallee/bindery/blob/main/docs/DEPLOYMENT.md#environment-variables). |

### Storage

| Option | Default | Meaning |
| --- | --- | --- |
| `library_dir` | `/media/books` | Where imported books go, as seen from inside the app. |
| `downloads_dir` | `/media/downloads` | Where your download client puts finished books, as seen from inside the app. |
| `audiobooks_dir` | *(empty)* | Optional separate folder for audiobooks. Empty keeps them in the library folder. |
| `audiobook_downloads_dir` | *(empty)* | Optional separate download folder for audiobooks. |
| `localdisks` | `[]` | External disks to mount. Empty means: use the Home Assistant folders only. |
| `dir_mode` | `0750` | Permissions of the folders Bindery creates. `0755` if another program must read the library as another user. |

Paths are the ones **inside the container**. The app exposes Home Assistant's folders at fixed
mount points, and any disk you list in `localdisks` at `/mnt/<device>`:

| Inside the app | What it is |
| --- | --- |
| `/media` | Home Assistant's `media` folder (the one the Media browser shows) |
| `/share` | Home Assistant's `share` folder |
| `/data` | The app's private folder: Bindery's database, backups, covers |
| `/mnt/sda1`, `/mnt/sdb1`, … | A disk you listed in `localdisks` |

## Using an external disk

Put the disk's device name in `localdisks`, for example `sda1`. The app log lists the devices it
can see on every start, with their labels and UUIDs:

```
[INFO] Disks visible in the container:
[INFO]   /dev/sda1: LABEL="MyBook" UUID="1a2b-…" TYPE="ext4"
```

Accepted forms:

| Value | Effect |
| --- | --- |
| `sda1` | Mount the whole filesystem at `/mnt/sda1` |
| `/dev/sda1` | Same thing, given as a path |
| `MyBook` | Mount the disk that carries that label |
| `1a2b3c4d-…` | Mount the disk that carries that UUID (unambiguous, recommended when two disks share a label) |
| `sda1/Media/Books` | Mount **only** that folder of the disk, at `/mnt/sda1/Media/Books` |

Then point `library_dir` and `downloads_dir` at folders of that mount, for example
`/mnt/sda1/Media/Books` and `/mnt/sda1/Downloads/books`.

Two rules the app enforces, both to protect your data:

- **If a listed disk cannot be mounted, the app stops.** Bindery creates missing library folders,
  so starting anyway would import books into a folder that disappears on the next restart.
- **A library path outside a mount is refused.** If `library_dir` is `/mnt/sda1/…` but `/mnt/sda1`
  is not mounted, the app stops with a message naming the path.

Detailed layouts, including several disks and the hardlink rules: [docs/STORAGE.md](https://github.com/NolanMlb/hassio-addons-bindery/blob/main/docs/STORAGE.md).

## Connecting Prowlarr and qBittorrent

Both are configured **inside Bindery**, in *Settings → Indexers* and *Settings → Download clients*.
The app does not duplicate those credentials as options: Bindery stores them in its own database,
its connection tests and its save-path checks are the ones that matter, and keeping a second copy
in `options.json` would only be a way to break them silently.

Practical points for a Home Assistant installation:

1. **Addresses.** Use the address the other app answers on *from the Bindery container*. Both apps
   usually publish a port on the Home Assistant host, so `http://<home-assistant-ip>:9696`
   (Prowlarr) and `http://<home-assistant-ip>:8080` (qBittorrent) work. A container name only
   resolves if both containers share a Docker network, which the Supervisor does not do for you.
2. **Paths must match.** If qBittorrent saves to `/media/downloads` and Bindery reads
   `/media/downloads`, nothing needs configuring. If qBittorrent sees your disk at another path,
   add a path remap in Bindery (*Settings → Download clients*) or set
   `BINDERY_DOWNLOAD_PATH_REMAP` through `env_vars`.
3. **Category.** Use a category for books (e.g. `books`) whose save path is the same folder as
   `downloads_dir`. Bindery checks that mapping and warns when it does not line up.
4. **Loopback.** Bindery refuses indexer-provided download links that point at `127.0.0.1`. If
   Prowlarr only answers on loopback, reach it by a LAN address instead, or add
   `BINDERY_DOWNLOAD_ALLOW_LOOPBACK=true` to `env_vars`.

## Updating

The version of this app is `<Bindery version>-<app revision>`, for example `1.48.0-1`. Home
Assistant shows the update when a new image is published; installing it replaces the container
and keeps `/data`.

- Bindery applies its own database migrations on start — that is how upstream upgrades work.
- Take a backup before a minor version bump: *Settings → Logs → Backup & Restore → Create Backup*
  inside Bindery, or a Home Assistant snapshot (the app is stopped during a snapshot so the SQLite
  file is copied consistently).
- Rolling back is possible: install the previous app version from the store's version selector.

## Where things live

| Data | Location | Survives restart | In a snapshot |
| --- | --- | --- | --- |
| Database, backups, cover cache | `/data/bindery` | yes | yes |
| Options | `/data/options.json` | yes | yes |
| Library, downloads | wherever you pointed them | yes, if on a mapped folder or a mount | only if in `/media` or `/share` |
| Books on an external disk | on the disk | yes | no — the disk is not in Home Assistant's snapshot |

## Troubleshooting

The app log is the first place to look; it prints the storage summary, the visible disks, every
mount and its result on each start, and it stops the app with an explicit message when a disk is
missing or Bindery keeps crashing. Common cases — a disk that does not appear, `permission
denied`, a library that stays empty, a `403` on a domain name — are covered in
[docs/TROUBLESHOOTING.md](https://github.com/NolanMlb/hassio-addons-bindery/blob/main/docs/TROUBLESHOOTING.md).

The web interface is served on port `8787` of the app (`http://<home-assistant>:8787`); to use
another port, change it in the app's **Network** settings, not in the options, because the
*Open Web UI* button and the health check point at the mapped port.
