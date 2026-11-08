# Home Assistant App: Bindery

Automated ebook and audiobook manager, the modern replacement for Readarr. Monitor authors,
search indexers through Prowlarr, download with qBittorrent, and let Bindery rename and file
the books in your library.

This app is a deployment layer around the official Bindery image. Bindery's own web interface,
API and features are untouched: the binary is copied verbatim from
`ghcr.io/vavallee/bindery`, so upstream releases reach you without a fork.

## What this app adds

- Bindery's database and configuration in the app's persistent `/data` folder, kept across
  restarts, updates and snapshots.
- Configurable storage: Home Assistant's `/media` and `/share` folders, an external USB/SATA
  disk, several disks, or one folder of a disk — with the paths exposed as options instead of
  being hardcoded.
- Downloads and library on the same filesystem by default, so imports are hardlinks.
- A Docker health check on Bindery's own health endpoint, and a startup that refuses to run when a
  configured disk is missing.

## What it does not do

- It does not reimplement Bindery. Prowlarr and qBittorrent are configured inside Bindery's
  web interface, exactly as documented upstream.
- It does not proxy or expose your interface to the internet. Remote access is your reverse
  proxy or VPN, on your terms.
