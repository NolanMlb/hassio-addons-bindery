# Install

## Requirements

- Home Assistant OS (or Supervised) with the app store available.
- 200 MB free for the image, plus room for the library wherever you put it.
- `aarch64` (64-bit ARM: Raspberry Pi 4/5, ODROID, Green, Yellow) or `amd64` (x86-64: NUC, Proxmox
  VM, generic install). 32-bit ARM is not supported: upstream publishes no container image for it.

## Add the repository

1. **Settings → Apps → App store** (on older versions: *Add-on store*).
2. Open the three-dot menu (top right) → **Repositories**.
3. Paste `https://github.com/NolanMlb/hassio-addons-bindery` and confirm.
4. Close the dialog: **Bindery** now appears in the store, under *Bindery Home Assistant apps*.

Or use the badge on the [repository page](https://github.com/NolanMlb/hassio-addons-bindery), which
opens your instance with the repository pre-filled.

## Install and first start

1. Open **Bindery** in the store and press **Install**. No build happens: the image is pulled from
   the GitHub Container Registry.
2. Go to the **Configuration** tab. The defaults work on a fresh installation:

   ```yaml
   log_level: info
   TZ: Europe/Paris        # your timezone
   PUID: 0
   PGID: 0
   localdisks: []
   library_dir: /media/books
   downloads_dir: /media/downloads
   ```

   Set only `TZ` if you want to start right away; everything else can change later.
3. **Start** the app, then watch the log once. A healthy start ends with lines like:

   ```
   [INFO] No localdisks configured: the app uses the Home Assistant folders only
   [INFO] Hardlinks available: library and downloads are on the same filesystem
   [INFO] Starting Bindery as 0:0 (data: /data/bindery, library: /media/books)
   {"level":"INFO","msg":"listening","addr":":8787"}
   ```

4. Press **OPEN WEB UI**. Bindery asks you to create the admin account, then walks you through its
   own setup checklist.

The app page shows a green **Running** state; the image's health check follows `GET /api/v1/health`, so a
Bindery that stops answering marks the app unhealthy.

## Choosing storage

Three questions decide everything:

1. **Where do the books live?** Home Assistant's `/media` folder (the media library), `/share`, or
   an external disk.
2. **Is that also where your download client writes?** If yes, you get hardlinks and no remap.
3. **Do you need snapshots to include the books?** Only `/media` and `/share` are in Home Assistant's
   snapshots; an external disk is not.

Read [STORAGE.md](./STORAGE.md) before setting up an external disk: it covers the four layouts, the
`localdisks` syntax and the hardlink rules.

## Connecting Prowlarr

Both apps run in containers on the Home Assistant host, so use published ports and a LAN address.
`127.0.0.1` inside Bindery means Bindery itself.

1. In Prowlarr: **Settings → General** shows the API key. Note the port (default `9696`).
2. In Bindery: **Settings → Indexers → Prowlarr**, add
   `http://<home-assistant-ip>:9696` and the API key, then **Sync**.
3. If Prowlarr itself runs in a Home Assistant app, its port is published on the host — the same
   address works from your browser and from Bindery.
4. Grabbing a release later fails if Prowlarr only answers on loopback; see
   [Troubleshooting](./TROUBLESHOOTING.md#prowlarr-or-qbittorrent-tests-fail).

## Connecting qBittorrent

1. In qBittorrent: **Settings → Web UI** gives the port (default `8080`) and lets you set a user and
   password. Bindery needs the Web UI reachable, not just the torrent port.
2. In Bindery: **Settings → Download clients → Add → qBittorrent**, address
   `http://<home-assistant-ip>:8080`, your credentials.
3. Create a category (e.g. `books`) in qBittorrent whose save path is the folder that
   `downloads_dir` points at — inside **both** containers. If the two apps see the disk at different
   paths, add a path remap in the same Bindery dialog:
   `/what/qbittorrent/sees:/what/bindery/sees`.
4. Back in Bindery, **Test** the client: the save-path check names the problem when the paths do not
   line up.

## Adding the first book

1. **Authors → Add**, search a name, pick the author, choose the root folder (the library folder)
   and a quality profile.
2. Bindery searches on its own schedule; **Search** forces it.
3. Follow the *Queue* page: `downloading` → `importing` → `imported`. On `importFailed`, the message
   names the path it could not read.

## Everyday maintenance

| Task | How |
| --- | --- |
| Change a folder | Configuration tab, then **Restart** |
| Change a disk | Configuration tab → `localdisks` → **Restart** |
| Update the app | **Settings → Apps** → update notice, or the store page |
| Back up | Bindery *Settings → Logs → Backup & Restore*, and/or a Home Assistant snapshot |
| See what the app sees | **Log** tab, first 20 lines of every start |

## Remote access

The app does not expose anything to the internet. To reach Bindery from outside:

- a VPN (WireGuard/Tailscale app) and the internal address, or
- your own reverse proxy with TLS, pointed at port 8787, plus `BINDERY_ALLOWED_HOSTS` and
  `BINDERY_TRUSTED_PROXY` through `env_vars`.

Never port-forward 8787 directly: Bindery's login is only as strong as the password you set, and it
would be exposed over plain HTTP.
