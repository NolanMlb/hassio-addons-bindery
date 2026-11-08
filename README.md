# Bindery for Home Assistant

A Home Assistant app repository that runs [Bindery](https://github.com/vavallee/bindery) — an automated
ebook and audiobook manager, the modern replacement for Readarr — the same way the
Radarr/Sonarr apps run: add the repository, install, fill in your paths, open the web
interface.

[![Open your Home Assistant instance and show the app store with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_store.svg)](https://my.home-assistant.io/redirect/supervisor_store/?repository_url=https%3A%2F%2Fgithub.com%2FNolanMlb%2Fhassio-addons-bindery)

## Apps

### [Bindery](./bindery)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

Automated ebook and audiobook manager with Prowlarr and qBittorrent support.

- Uses the **official `ghcr.io/vavallee/bindery` image**: the binary is copied from it, never
  rebuilt or forked, so you get Bindery's own UI, API, features and release cadence.
- Storage is **configurable, never assumed**: Home Assistant's `/media` and `/share` folders
  work out of the box, external disks are opt-in through a `localdisks` option.
- One mount for downloads and library by default, so imports are **hardlinks** (instant, no
  extra disk) instead of copies.
- Nothing about the maintainer's own installation is baked in: no host path, IP, API key or
  disk name appears anywhere in the code.

## Install

1. Home Assistant → **Settings → Apps → App store** (older versions: Add-on store).
2. Three-dot menu → **Repositories** → paste
   `https://github.com/NolanMlb/hassio-addons-bindery` → **Add**.
3. Install **Bindery**, set your folders, start it, then **Open Web UI**.

Full instructions: [docs/INSTALL.md](./docs/INSTALL.md). Storage layouts (Home Assistant
folders, USB disk, several disks): [docs/STORAGE.md](./docs/STORAGE.md).

## Documentation

| Document | What it covers |
| --- | --- |
| [bindery/DOCS.md](./bindery/DOCS.md) | The app's own documentation, also shown in Home Assistant |
| [docs/INSTALL.md](./docs/INSTALL.md) | Install, first start, connecting Prowlarr and qBittorrent |
| [docs/STORAGE.md](./docs/STORAGE.md) | Every storage layout, with the hardlink and path-remap details |
| [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) | Symptoms and fixes, starting with the log lines to look for |
| [docs/AUDIT.md](./docs/AUDIT.md) | The technical audit this app is built on: what Bindery actually supports |
| [docs/SECURITY.md](./docs/SECURITY.md) | Privileges, network exposure, secrets, backups |
| [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) | Build, run and test locally with Docker |
| [docs/PUBLISHING.md](./docs/PUBLISHING.md) | Publish the repository and release a new version |
| [docs/ROADMAP.md](./docs/ROADMAP.md) | What is deliberately not implemented yet, and why |

## Project status

Verified in this repository (see [tests/smoke-test.sh](./tests/smoke-test.sh), 28 assertions):

- image builds for `linux/amd64` and `linux/arm64`, and the amd64 binary runs (health check
  reaches Bindery);
- the app starts, answers `GET /api/v1/health` with `200`, creates its database in its
  persistent `/data` folder, and keeps it across a restart;
- storage on `/media` only, with no external disk;
- a real block device (ext4, on a loop device) mounted by label into `/mnt/<disk>`, Bindery
  writing its library there, and a hardlink between downloads and library succeeding;
- mounting a single folder of a disk, without exposing the rest of it;
- `PUID`/`PGID` 1000: Bindery confirms the pair at startup and the data folder is owned by it;
- a disk that cannot be mounted stops the app instead of silently writing to a transient
  folder;
- a library path outside any mount is refused;
- a Bindery that keeps crashing stops the app after six restarts in five minutes instead of
  looping silently.

Not verified here: an installation on a physical Home Assistant OS device. Everything the app
relies on (the Supervisor's `map`, `devices`, option schema, S6 base image, `HEALTHCHECK`) is the
documented, standard mechanism, but if you install it on your own box and something looks
wrong, please open an issue with the app log.

## Credits

- [Bindery](https://github.com/vavallee/bindery) by vavallee (MIT) — the application itself.
- [home-assistant/apps-example](https://github.com/home-assistant/apps-example) — the repository
  and CI layout this one follows.
- [alexbelgium/hassio-addons](https://github.com/alexbelgium/hassio-addons) — the reference for
  a configurable storage experience (`localdisks`); this app reimplements the idea from scratch
  so it does not depend on his image internals.

## License

MIT for this repository's own code. Bindery remains MIT, by its own author; its licence and
third-party notices ship inside the image at `/BINDERY_LICENSE` and
`/BINDERY_THIRD_PARTY_LICENSES.md`.

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
