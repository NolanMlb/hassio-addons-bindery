<!-- https://contributors.home-assistant.io/apps/guides/presentation/#changelog -->
## 1.48.0-1

Initial release.

- Runs the official Bindery image (`ghcr.io/vavallee/bindery:1.48.0`): the binary is copied from the
  upstream image, never rebuilt or forked.
- Bindery's database, backups and cover cache live in the app's persistent `/data` folder, included
  in Home Assistant snapshots and kept across updates.
- Storage is fully configurable: `library_dir`, `downloads_dir`, optional audiobook folders, and a
  `localdisks` option for external disks (whole disk, by label, by UUID, or a single folder).
- Downloads and library share one mount by default, so imports are hardlinks; the startup log says
  which mode is in effect.
- The app refuses to start when a configured disk is missing or when a library path is outside a
  mount, instead of writing into a folder that would disappear on restart.
- `PUID`/`PGID` support (root entrypoint drops privileges, then asserts the pair to Bindery),
  `dir_mode`, `TZ`, `log_level`, telemetry opt-out and a masked `env_vars` passthrough for the rest
  of Bindery's documented `BINDERY_*` variables.
- Watchdog on Bindery's own `/api/v1/health`, and `backup: cold` so snapshots copy a consistent
  SQLite database.
- `aarch64` and `amd64` only, matching the architectures upstream actually publishes.
