# https://contributors.home-assistant.io/apps/guides/dockerfile/
#
# The app is a thin deployment layer around the official Bindery image:
# the binary is copied verbatim from it, never rebuilt, patched or forked, so
# users get Bindery's own UI, API, features and release cadence.

ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24
# Bump this to follow Bindery releases (see CHANGELOG.md). Renovate handles it.
ARG BINDERY_VERSION=1.48.0
ARG BINDERY_REPOSITORY=ghcr.io/vavallee/bindery

FROM ${BINDERY_REPOSITORY}:${BINDERY_VERSION} AS upstream

FROM ${BUILD_FROM}

# Fail the container when a preparation script fails instead of starting
# Bindery on top of a half-mounted installation.
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# util-linux: mount, blkid, lsblk, mountpoint (busybox tools are too limited to
# reliably identify and mount arbitrary filesystems).
# ntfs-3g: NTFS read/write when the kernel has no ntfs3 driver.
# exfatprogs: tools for exFAT volumes.
# Package versions are not pinned: the image is rebuilt on every app release, and
# a pinned Alpine package disappears from the repository on the next point
# release, which would break the build for no security gain (apk verifies
# signatures and the base image tag pins the Alpine release).
# hadolint ignore=DL3018
RUN apk add --no-cache \
    util-linux \
    ntfs-3g \
    exfatprogs \
    && rm -rf /var/cache/apk/*

# The official Bindery binary (statically linked, CGO_ENABLED=0) and the
# attribution its licence requires us to redistribute with it.
COPY --from=upstream /bindery /usr/bin/bindery
COPY --from=upstream /LICENSE /BINDERY_LICENSE
COPY --from=upstream /THIRD_PARTY_LICENSES.md /BINDERY_THIRD_PARTY_LICENSES.md

COPY rootfs /

RUN chmod 755 /usr/bin/bindery \
    && chmod 755 /usr/lib/bindery/common.sh \
    && chmod 755 /etc/cont-init.d/00-bindery.sh \
    && chmod 755 /etc/services.d/bindery/run \
    && chmod 755 /etc/services.d/bindery/finish

LABEL \
    org.opencontainers.image.title="Home Assistant App: Bindery" \
    org.opencontainers.image.description="Automated ebook and audiobook manager (Readarr replacement)" \
    org.opencontainers.image.source="https://github.com/NolanMlb/hassio-addons-bindery" \
    org.opencontainers.image.documentation="https://github.com/NolanMlb/hassio-addons-bindery/blob/main/bindery/DOCS.md" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.vendor="NolanMlb"

# Bindery answers /api/v1/health with 200 once it is serving.
# The shell form is needed to turn curl's exit status into HEALTHCHECK's.
# hadolint ignore=DL3025
HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=20s \
    --retries=3 \
    CMD curl -fsS --max-time 4 http://127.0.0.1:8787/api/v1/health || exit 1
