# Publishing

The repository is ready to be pushed as-is. Nothing in it points at a machine of a particular
user: the only place your GitHub account appears is the image name and the URLs, and both are
replaced in one pass below.

## 1. Push the repository

```bash
cd hassio-addons-bindery
git remote add origin git@github.com:NolanMlb/hassio-addons-bindery.git
git push -u origin main
```

If you publish under a different account or name, replace them everywhere first:

```bash
grep -rl "NolanMlb" . | xargs sed -i '' 's/NolanMlb/<your-account>/g'
sed -i '' 's#ghcr.io/nolanmlb/#ghcr.io/<your-account>/#' bindery/config.yaml
```

(The image name must stay **lowercase**: a container registry rejects an uppercase path.)

Also update the `if: github.repository == …` guard at the top of
`.github/workflows/build-app.yaml`.

## 2. First build

Push to `main` with `bindery/config.yaml`, `bindery/Dockerfile` or `bindery/rootfs/` changed, and
`.github/workflows/builder.yaml` builds the app for `amd64` and `aarch64`, then publishes the
multi-arch manifest:

```
ghcr.io/<account>/hassio-addons-bindery:<version>
ghcr.io/<account>/hassio-addons-bindery:latest
```

Watch it in the **Actions** tab. If the workflow cannot push, check **Settings → Actions → General
→ Workflow permissions** (read and write) and that Actions is enabled for the repository.

## 3. Make the package public — required

The first push creates a **private** package. Users cannot pull a private image, and the install
fails with a `401` on the manifest.

1. GitHub → your profile → **Packages** → `hassio-addons-bindery`.
2. **Package settings → Danger Zone → Change visibility → Public**.
3. Confirm the package is linked to the repository (same page, *Manage access*).

Do this before announcing the repository.

## 4. Install from the published repository

1. Home Assistant → **Settings → Apps → App store** → three-dot menu → **Repositories**.
2. Add `https://github.com/<account>/hassio-addons-bindery`.
3. Install **Bindery**. The Supervisor pulls `ghcr.io/<account>/hassio-addons-bindery:<version>` —
   the tag is the `version` in `config.yaml`, which is why that key and the published tag must
   always match.

## 5. Releasing an update

`version` in `config.yaml` is the single source of truth: it is what users see, what the Supervisor
pulls, and what decides whether an update is offered.

1. Change the code (or `ARG BINDERY_VERSION` in the Dockerfile).
2. Bump `version` — `<bindery version>-<app revision>`, e.g. `1.48.0-2`.
3. Add the entry at the top of `bindery/CHANGELOG.md`.
4. Commit and push. CI builds `<version>` and `latest`; `.github/workflows/release.yaml` creates the
   `v<version>` tag and the GitHub release from the changelog entry.

Order matters: the image must exist before users update, and the store only offers the update once
`config.yaml` carries the new version. Building on the same push satisfies both, because the
Supervisor pulls by tag only when a user installs or updates.

**Never publish only `latest`.** The Supervisor pulls the exact `version`, so a `latest`-only
release is invisible to users and cannot be rolled back.

## 6. Rolling back

Tags are immutable in practice (do not overwrite one). To roll back: bump `version` to a new number,
set `ARG BINDERY_VERSION` back to the previous Bindery release, and publish. Users update normally,
and `/data` is untouched — Bindery migrates its database forward, so a rollback across a Bindery
minor version may need a backup restore.

## 7. Keeping up with Bindery

`.github/renovate.json` teaches Renovate to read `ARG BINDERY_VERSION` and open a PR when upstream
publishes a new image tag. Merging that PR is not enough on its own: the app `version` must change
too, otherwise the Supervisor sees the same tag and offers no update. Renovate's PR is therefore a
reminder, not an automatic release — the checklist above still applies.

A GitHub Action could automate it (read the upstream release, bump both keys, commit); it is not
wired here because a broken release flow that publishes without a changelog is worse than a manual
release that takes two minutes.

## 8. Repository checklist before announcing

- [ ] `ghcr.io/<account>/hassio-addons-bindery:1.48.0-1` exists and is **public**
- [ ] the manifest lists both `linux/amd64` and `linux/arm64`
      (`docker buildx imagetools inspect ghcr.io/<account>/hassio-addons-bindery:latest`)
- [ ] the Lint workflow is green (app linter, shellcheck, hadolint, yamllint)
- [ ] `bindery/config.yaml` has a `description` under 100 characters, icons, and `stage` you are
      comfortable with
- [ ] the install flow works on a clean Home Assistant instance
- [ ] `repository.yaml` names the repository and its maintainer
