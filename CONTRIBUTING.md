# Contributing

Issues and pull requests are welcome, in English or in French.

## Before opening an issue

- Read [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md): most reports are a path that does not
  match between the app and the download client, or a disk that is not visible to the container.
- Include the app log from the start of the container (the part with the `[INFO]` lines), your
  options **with secrets removed**, and the Home Assistant and Bindery versions.

## Pull requests

- Keep the app a thin layer: if a feature can be configured inside Bindery, it belongs in Bindery,
  not here.
- No installation-specific value in `rootfs/`. If a value depends on the user, it is an option.
- Run `make lint` and `make test` — both must pass.
- Update `bindery/DOCS.md` and `bindery/CHANGELOG.md` with the change, and `bindery/translations/*`
  if you add an option.
- One topic per pull request. A version bump on its own is fine.

## Style

- Shell: POSIX-ish Bash, `set -euo pipefail`, `shellcheck -S warning` clean, comments explain *why*.
- YAML: two spaces, quoted versions (`"1.48.0-1"`), long descriptions avoided — the interface shows
  `translations/*.yaml` instead.
- Documentation: present tense, second person, concrete paths. Say what a thing does, not how
  impressive it is.
