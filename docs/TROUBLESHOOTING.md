# Troubleshooting

Start with the app log (**Settings → Apps → Bindery → Log**). Every start prints the storage
summary, the block devices the container can see, each mount with its result, and the folders
Bindery will use. Set `log_level` to `debug` for more.

---

## The app stops right after starting

The startup script deliberately refuses to run when a storage rule is broken, because Bindery would
otherwise create the missing folders inside the container and import books into a folder that
disappears at the next restart.

### `localdisks: 'sdb1' matches no device, UUID or label visible in the container`

The disk is not visible to the container. Check, in this order:

1. The disk is plugged in and the log's *"Disks visible in the container"* list shows it.
2. Its device node is in the app's `devices:` list in `config.yaml`. The Supervisor only binds the
   nodes an app declares — a disk that appears as `/dev/sdh1` on the host is invisible if only
   `/dev/sda…sdg` are declared. Declaring a node requires editing `config.yaml` (a fork, or an
   issue asking for the device to be added).
3. The disk is not a partition of a disk already mounted elsewhere: two mounts of the same
   filesystem are refused by the kernel.

Use the label or the UUID instead of the device name when the name changes between boots
(`MyBook`, or `1a2b3c4d-…`).

### `library '/mnt/sda1/Media/Books' is not inside a mounted disk`

The path in `library_dir` (or `downloads_dir`) is not under any mount. Either:

- the disk is not listed in `localdisks`, or
- you mounted only one folder (`sda1/Media/Books`) and the path points elsewhere on that disk.

Align the two: the path must start with the mount point the app actually created, which the log
names (`mounted at …`).

### `the folder 'X' does not exist on sda1 (case sensitive)`

Folder-only mounts require the exact case: `sda1/Media/Books` is not `sda1/media/books`.

### `localdisks: /dev/sda1 could not be mounted`

- **Unsupported filesystem.** The log prints the filesystems the kernel supports
  (*"Supported fs"*-style list is not printed, but `mount` fails with `unknown filesystem type`).
  exFAT/NTFS are supported through the kernel or `ntfs-3g`; ZFS, F2FS variants and anything needing
  an out-of-tree module are not.
- **Dirty filesystem.** A disk unplugged while writing can need a repair (`fsck`) before it mounts.
  Do that on another machine; the app has no repair tool.
- **Partition table but no filesystem.** `localdisks: sda` mounts the whole-disk node; use `sda1` for
  the partition.

### `Bindery was started 7 times in 26s: giving up.`

The app itself stopped because Bindery kept exiting right after starting. The lines above the message
name the cause — usually a database that cannot be opened (permissions on `/data/bindery`) or a
library folder that is not writable. Fix it, then start the app again; the counter resets after five
minutes of a healthy run.

---

## The disk is not in the list at all

The list comes from the device nodes the Supervisor handed to the container. If the disk was
plugged in *after* the app started, restart the app: device nodes are bound at container start.

## `permission denied` when Bindery writes

- Check the startup warning `… is not writable by <PUID>:<PGID>`.
- `PUID`/`PGID` must match the user that owns the folders. The default `0:0` matches download
  clients running as root. If you set `PUID=1000`, your download client must do the same, and the
  folders it wrote before the change still belong to root: `chown -R 1000:1000` them once, from a
  terminal app.
- On FAT/exFAT/NTFS, ownership is emulated at mount time (`uid`, `gid`, `umask`); a remount of the
  app is enough after changing `PUID`/`PGID`.

## Imports are copies, not hardlinks

The log says either `Hardlinks available…` or warns that the two folders are on different
filesystems. A copy means one of:

- `library_dir` and `downloads_dir` are on two different mounts (two disks, or `/media` versus
  `/mnt/sda1`);
- you mounted a folder of a disk for the library and the whole disk for the downloads;
- your download client reports a path Bindery resolves elsewhere, so the *import source* is not
  `downloads_dir` at all — check the remap in *Settings → Download clients*.

Mount the whole disk once and use two folders of it.

## The web interface does not answer

1. Is the app running? **Settings → Apps → Bindery** shows the state; the log must end with
   `listening`, `addr=:8787`.
2. `http://<home-assistant-ip>:8787` — plain HTTP, port 8787 by default. If you changed the port in
   the app's **Network** settings, use that one; the *Open Web UI* button follows the mapping.
3. If Home Assistant is on `https://…` through a reverse proxy, the app is not automatically behind
   it: reaching it by HTTPS needs your own proxy pointed at port 8787.

## `403` / login page on a domain name

Bindery's `local-only` mode only serves names it considers local (IP addresses, `.local`, `.lan`,
`.home.arpa`, single-label names). A domain such as `books.example.com` is refused until it is
allow-listed:

```yaml
env_vars:
  - name: BINDERY_ALLOWED_HOSTS
    value: books.example.com
```

Behind a TLS proxy, also set `BINDERY_TRUSTED_PROXY` to the proxy's address, otherwise Bindery
treats every request as coming from the proxy and builds `http://` links.

## Prowlarr or qBittorrent tests fail

- **Address.** Bindery runs in its own container. `127.0.0.1` is Bindery itself. Use the Home
  Assistant host's LAN address and the published port, e.g. `http://192.168.1.10:9696`.
- **Loopback download links.** With Prowlarr on loopback, the indexer *test* passes (admin-typed
  URL) but grabbing fails, because the download link it returns points at `127.0.0.1`. Reach
  Prowlarr through a LAN address, or add
  `BINDERY_DOWNLOAD_ALLOW_LOOPBACK=true` to `env_vars`.
- **qBittorrent save path.** Set the category's save path to the same folder as `downloads_dir`,
  seen from Bindery. Bindery checks this and tells you which side is wrong.

## A download sits in `importFailed` / `importBlocked`

Nothing to do with the app: Bindery cannot see the files at the path the client reported. Fix the
path (remap, category save path) and use **Queue → Retry import**; the release is not downloaded
again. `importBlocked` after ~30 minutes means the client kept reporting a finished download whose
files never appeared at that path.

## The database looks empty or the setup redirects in a loop

- A wrong `library_dir` never empties the database — the database lives in `/data/bindery`. If books
  disappeared from the library, check the folder first.
- If the interface keeps sending you to `/setup`, the browser may be using an old cookie for a
  different host name; try the IP address, or clear the site's cookies.

## After a restart, the library folder is empty

The disk did not mount on this boot. With `localdisks` configured and a disk missing, the app stops
instead of starting (that is the guard working). Check the log's device list: a disk that changed
from `sda1` to `sdb1` after a reboot should be referenced by label or UUID.

## Recovering a database

Bindery keeps its own backups in `/data/bindery/backups`, created when you use *Settings → Logs →
Backup & Restore* (or `POST /api/v1/backup`). To restore, stop the app, replace
`/data/bindery/bindery.db` with a backup copy, and start it again.

Backups contain credentials in clear text — indexer keys, client passwords, the API key. Treat a
backup file like the keys it holds.

## Reporting a problem

Open an issue with:

- the app version (from the app page) and the Bindery version (the first log line names it);
- the app log, from the start of the container to the error, with `log_level: debug`;
- your options **with secrets removed** (`env_vars` values, nothing else is secret);
- whether the storage is `/media`, `/share`, an external disk, or several.
