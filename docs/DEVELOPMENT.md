# Development

The app is small on purpose: a Dockerfile, one preparation script, one service script, an AppArmor
profile and the app metadata. Everything Bindery does stays in Bindery.

## Layout

```
bindery/
├── config.yaml                  app metadata, options, schema, capabilities, mappings
├── Dockerfile                   base image + the official Bindery binary
├── apparmor.txt                 profile for the mount/chown/exec path
├── icon.png, logo.png           store artwork (assets/generate-icons.py)
├── translations/{en,fr}.yaml    option labels and help texts
├── DOCS.md                      the Documentation tab
├── CHANGELOG.md                 release notes (read by the store)
└── rootfs/
    ├── usr/lib/bindery/common.sh            option reading, logging, path helpers
    ├── etc/cont-init.d/00-bindery.sh        runs once, as root: timezone, disks, folders, ownership
    └── etc/services.d/bindery/{run,finish}  translates options to BINDERY_* and execs the binary
```

`rootfs/` is copied over the base image, so paths are the container's paths.

## Build

```bash
make build                 # docker build -t bindery-ha:test bindery
make build-multiarch       # buildx build for linux/amd64 and linux/arm64 (no load)
```

or directly:

```bash
docker build -t bindery-ha:test bindery
```

## Run it like the Supervisor does

The app reads its options from `/data/options.json`, so faking a Supervisor is enough:

```bash
mkdir -p /tmp/bt/{data,media,share}
cat > /tmp/bt/data/options.json <<'JSON'
{"log_level":"debug","TZ":"Europe/Paris","PUID":0,"PGID":0,"localdisks":[],
 "library_dir":"/media/books","downloads_dir":"/media/downloads","audiobooks_dir":"",
 "audiobook_downloads_dir":"","dir_mode":"0750","telemetry":false,"env_vars":[]}
JSON

docker run --rm -it -p 8787:8787 \
  -v /tmp/bt/data:/data -v /tmp/bt/media:/media -v /tmp/bt/share:/share \
  bindery-ha:test
```

`http://localhost:8787` answers exactly as it does inside Home Assistant, and every `[INFO]` line the
startup script prints can be read in the terminal.

To exercise the disk code, give the container a block device and list it in `localdisks`:

```bash
docker run --rm -it --privileged --device /dev/sda1 \
  -v /tmp/bt/data:/data -v /tmp/bt/media:/media bindery-ha:test
```

## Tests

```bash
make test          # 28 assertions, builds the image first
make test-no-build # against the existing image
```

`tests/smoke-test.sh` covers: default storage on `/media`, the database surviving a restart,
`PUID`/`PGID`, `env_vars` passthrough and its guards, an ext4 disk mounted by label with a hardlink
proof, a folder-only mount, a missing disk stopping the app, a library path outside a mount being
refused, and the crash-loop breaker that stops the app after six restarts.

Disk tests build a loop device inside a privileged container; they are skipped when the Docker
daemon does not allow that.

## Lint

```bash
make lint      # shellcheck + hadolint + yamllint, all in containers
```

All four scripts must pass `shellcheck -S warning`. `hadolint` runs with the two rules ignored in
`.hadolint.yaml` (unpinned `apk add`, shell-form `HEALTHCHECK`), both explained in the Dockerfile.

## How options flow

```
options.json ──► common.sh opt()/opt_list() ──► 00-bindery.sh   (dirs, mounts, ownership)
                                           └──► services.d/bindery/run  (BINDERY_* env + exec)
```

Rules to keep:

- **No installation-specific value in the code.** A path, an address, a disk name or a credential
  never appears in `rootfs/`; if a value is needed, it becomes an option or a `BINDERY_*` variable.
- **Defaults must work on a stock installation.** `/media/books` and `/media/downloads` exist as
  soon as the media folder is mapped.
- **Fail loudly** when a configured disk is missing: Bindery creates missing folders, so a silent
  fallback loses data.
- **Never read options with `bashio` only.** Plain `jq` on `${OPTIONS_FILE}` keeps the scripts
  runnable outside Home Assistant, which is what the smoke tests rely on.

## Following a Bindery release

1. Read the upstream changelog for breaking changes (schema or config).
2. Update `ARG BINDERY_VERSION` in `Dockerfile` (Renovate also opens this as a PR).
3. Set `version` in `config.yaml` to `<bindery version>-1`.
4. Add the entry to `CHANGELOG.md`.
5. `make test`, then merge: CI builds and publishes `<version>` and `latest`, and tags the release.

## Adding an option

1. `options` (default) and `schema` (type) in `config.yaml`.
2. A label in `translations/en.yaml` and `translations/fr.yaml`.
3. Read it in whichever script needs it, and export the matching `BINDERY_*` variable if upstream
   has one — check `docs/DEPLOYMENT.md` upstream rather than inventing a name.
4. A line in `DOCS.md`, and a case in the smoke tests if it can regress.

Prefer `env_vars` over a new option for anything upstream documents but that only a minority needs:
the options form should stay short.

## Icons

`python3 assets/generate-icons.py` writes `bindery/icon.png` (128×128) and `bindery/logo.png`
(250×100). Stdlib only, no image tooling required.
