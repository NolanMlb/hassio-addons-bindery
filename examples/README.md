# Example configurations

Copy-paste starting points for the app's **Configuration** tab. They are examples, not defaults:
every path below is inside the container, and only `/media`, `/share` and `/mnt/<disk>` exist there.

| File | Layout |
| --- | --- |
| [options-default.yaml](./options-default.yaml) | Home Assistant media folder only, no external disk |
| [options-usb-disk.yaml](./options-usb-disk.yaml) | One external disk mounted whole, hardlinks, audiobooks included |
| [options-folder-mount.yaml](./options-folder-mount.yaml) | Only one folder of a disk is exposed |
| [options-two-disks.yaml](./options-two-disks.yaml) | Library and downloads on one disk, audiobooks on another |

See [../docs/STORAGE.md](../docs/STORAGE.md) for what each layout implies.
