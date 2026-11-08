# Storage

Everything in this page is about one thing: making Bindery, your download client and Home
Assistant agree on **where the files are**, so that imports are hardlinks and nothing is copied
twice or lost on restart.

## The mental model

There are two namespaces, and they are not the same:

```
Home Assistant OS host                    inside the Bindery app
─────────────────────                     ─────────────────────
/mnt/data/supervisor/media  ──── /media ──►  /media
/mnt/data/supervisor/share  ──── /share ──►  /share
/mnt/data/supervisor/addons/data/bindery ──► /data       (database, options)
/mnt/sda1 (your USB disk)   ──── not mounted by the Supervisor
                                          /mnt/sda1     (only if you list it in `localdisks`)
```

The Supervisor only bind-mounts the folders an app declares in `map`. This app declares two:
`media` (read-write) and `share` (read-write). Everything else — an external disk — is mounted
**inside the app's own container** by its startup script, which is why it is opt-in through the
`localdisks` option and invisible to the other apps.

Consequence: **the paths in the options are the paths inside the app.** `/media/books` means the
folder named `books` in Home Assistant's media library. `/mnt/sda1/Media/Books` means the folder on
the disk mounted at `/mnt/sda1`.

## Layout A — Home Assistant folders only (the default)

No external disk. Works on any installation, including a single SD card.

```yaml
library_dir: /media/books
downloads_dir: /media/downloads
localdisks: []
```

```
/media                 (Home Assistant media folder)
├── books/             → Bindery's library
└── downloads/         → completed downloads, read by Bindery
```

- Hardlinks: yes, both folders are on the same mount.
- In snapshots: only if your snapshots include the media folder — they do not by default. Books
  survive restarts and updates, but a snapshot does not carry them.
- Your download client must also see these folders at these paths. Most qBittorrent/SABnzbd apps
  map Home Assistant's media folder at `/media`, which makes this layout work with no remap.

## Layout B — one external disk (recommended for a real library)

The whole disk is mounted once, and both folders are subfolders of it. This is the layout that
gives hardlinks, survives updates, keeps the library off the SD card, and matches what the
\*arr guides call the `/data` layout.

```yaml
localdisks:
  - sda1
library_dir: /mnt/sda1/Media/Books
downloads_dir: /mnt/sda1/Downloads/books
```

```
/mnt/sda1               (whole disk mounted once)
├── Downloads/
│   ├── incomplete/
│   ├── movies/
│   ├── tv/
│   └── books/          → Bindery's downloads_dir
└── Media/
    ├── Movies/
    ├── TV/
    └── Books/          → Bindery's library_dir
        ├── Ebooks/
        └── Audiobooks/ → audiobooks_dir (optional)
```

Then, in the download client:

- give qBittorrent/SABnzbd the **same** paths. If your client also runs in a Home Assistant app
  that mounts `/mnt/sda1` itself (its own `localdisks`), use `/mnt/sda1/Downloads/books` there too
  and no remap is needed;
- if the client cannot mount the disk and writes to `/media/downloads` instead, add a remap in
  Bindery (*Settings → Download clients → path remap*) or with `env_vars`:
  `BINDERY_DOWNLOAD_PATH_REMAP=/media/downloads:/mnt/sda1/Downloads/books`;
- create a category (e.g. `books`) whose save path is `downloads_dir`.

## Layout C — only one folder of a disk

If the disk holds other things you would rather not expose, mount a single folder. The rest of the
disk stays invisible inside the app.

```yaml
localdisks:
  - sda1/Media/Books
library_dir: /mnt/sda1/Media/Books
downloads_dir: /mnt/sda1/Media/Books/downloads
```

The folder must exist on the disk (case sensitive). Only that folder is mounted; `/mnt/sda1` itself
is not a mount point.

Caveat: a folder-only mount is one mount. If your downloads live in a **different** folder of the
same disk, mounting both separately gives two mounts, and Bindery will copy instead of hardlinking.
The app warns about this at startup (`library … and downloads … are on two different filesystems`).
Mount the whole disk when you care about hardlinks.

## Layout D — several disks

```yaml
localdisks:
  - sda1          # ebooks + downloads
  - sdb1          # audiobooks on a second disk
library_dir: /mnt/sda1/Media/Books
downloads_dir: /mnt/sda1/Downloads/books
audiobooks_dir: /mnt/sdb1/Audiobooks
```

Each disk is mounted at `/mnt/<device name>`. Bindery can use any of them; only hardlinks depend on
source and destination sharing one mount, so keep each download/library pair on the same disk.

## Hardlinks in one paragraph

Bindery's default import mode is `auto`: hardlink when the completed download and the library
folder are on the same **filesystem**, copy otherwise. A hardlink is instant, takes no extra space,
and lets a torrent keep seeding from the original file. "Same filesystem" is decided from inside the
app by the device ID, and two separate mounts have different device IDs even when they point at the
same physical disk. So: one mount, two folders inside it. The app checks this on every start and
prints either

```
[INFO] Hardlinks available: library and downloads are on the same filesystem
```

or a warning telling you the import will be a copy.

## Permissions

- `PUID`/`PGID` decide who owns what Bindery writes. `0:0` (the default) matches most download
  clients running as root in Home Assistant.
- If you set them to something else, use the **same** pair in your download client, and make sure
  the folders are writable by that user. The app checks the library and download folders at startup
  and tells you when they are not writable by `PUID:PGID` — it deliberately does not `chown`
  folders it does not own.
- `dir_mode` (default `0750`) is the permission given to the folders Bindery creates. Set `0755` if
  another program must read the library as a different user.
- FAT/exFAT/NTFS have no POSIX permissions; the app mounts them with `uid=PUID,gid=PGID,umask=022`
  so files appear owned by the app's user.

## Audiobooks

Audiobooks can share the library or live elsewhere:

```yaml
audiobooks_dir: /mnt/sda1/Media/Books/Audiobooks
audiobook_downloads_dir: ""     # empty: reuse downloads_dir
```

Empty `audiobooks_dir` makes Bindery file them inside the ebook library (upstream default:
`BINDERY_AUDIOBOOK_DIR` falls back to `BINDERY_LIBRARY_DIR`).

## Backups and updates

| Data | Where | Survives an update | In a Home Assistant snapshot |
| --- | --- | --- | --- |
| Database, cover cache, Bindery backups | `/data/bindery` | yes | yes |
| Options | `/data/options.json` | yes | yes |
| Library and downloads in `/media` or `/share` | Home Assistant folders | yes | only if the snapshot includes them |
| Library and downloads on an external disk | the disk | yes | **no** — the disk is not part of a snapshot |

The app is configured with `backup: cold`: Home Assistant stops it while the snapshot runs, so the
SQLite file is copied consistently rather than mid-write.

## Coming from a Docker or Unraid install

1. Stop the old container.
2. Copy its `/config` (the folder containing `bindery.db`) into the app's data folder. On the Home
   Assistant host, the app's persistent data is `/mnt/data/supervisor/addons/data/bindery/`; the
   files Bindery owns are in the `bindery` subfolder of it, so the database goes to
   `/mnt/data/supervisor/addons/data/bindery/bindery/bindery.db`. Use the *Advanced SSH & Web
   Terminal* app, or a file editor app, to copy them — and stop the app first.
3. Set `library_dir` and `downloads_dir` to paths that exist **inside the app** (`/media/...`,
   `/share/...` or `/mnt/<disk>/...`), not the old host paths.
4. Start the app, and in Bindery check *Settings → Download clients*: any path remap that named the
   old container paths is worth revisiting.

If the database comes from an older Bindery minor version, back it up first: Bindery migrates on
start and the migration is one-way.
