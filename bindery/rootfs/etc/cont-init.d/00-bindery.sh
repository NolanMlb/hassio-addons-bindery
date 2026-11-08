#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# ==============================================================================
# Bindery app - preparation (runs once, as root, before the service starts)
#
#   1. apply the configured timezone
#   2. list the block devices the container can see (helps the user fill
#      `localdisks`)
#   3. mount the disks the user listed in `localdisks`
#   4. create and validate the folders Bindery reads and writes
#   5. hand the app's own data folder to PUID:PGID
#
# A failed mount is fatal on purpose: Bindery creates missing library folders,
# so starting with an unmounted disk would silently import books into the
# container's ephemeral filesystem and lose them on the next restart.
# ==============================================================================
set -euo pipefail

# shellcheck source=/dev/null
. /usr/lib/bindery/common.sh

PUID="$(opt PUID 0)"
PGID="$(opt PGID 0)"
TZ_VALUE="$(opt TZ UTC)"
LIBRARY_DIR="$(opt library_dir /media/books)"
DOWNLOADS_DIR="$(opt downloads_dir /media/downloads)"
AUDIOBOOKS_DIR="$(opt audiobooks_dir "")"
AUDIOBOOK_DOWNLOADS_DIR="$(opt audiobook_downloads_dir "")"

# ------------------------------------------------------------------------------
# 1. Timezone
# ------------------------------------------------------------------------------
if [ -n "${TZ_VALUE}" ] && [ -f "/usr/share/zoneinfo/${TZ_VALUE}" ]; then
    ln -snf "/usr/share/zoneinfo/${TZ_VALUE}" /etc/localtime
    printf '%s\n' "${TZ_VALUE}" > /etc/timezone
    info "Timezone set to ${TZ_VALUE}"
else
    warn "Timezone '${TZ_VALUE}' is unknown, the container keeps UTC"
fi

# ------------------------------------------------------------------------------
# 2. Which disks are visible? Printed on every start, so a user can read the
#    answer straight from the app log instead of guessing device names.
# ------------------------------------------------------------------------------
list_available_disks() {
    local found=0 line
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        found=1
        info "  ${line}"
    done < <(blkid 2>/dev/null | sed -e 's/[[:space:]]*BLOCK_SIZE="[^"]*"//' \
                                   -e 's/[[:space:]]*PARTUUID="[^"]*"//' || true)
    if [ "${found}" -eq 0 ]; then
        info "  no block device is visible in the container"
    fi
}

# ------------------------------------------------------------------------------
# 3. Mounts
# ------------------------------------------------------------------------------
# Every visible /dev node whose UUID or label is <ident>, one per line.
devices_matching() {
    local ident="${1}" line dev uuid label
    while IFS= read -r line; do
        dev="${line%%:*}"
        uuid="$(blkid_field "${line}" UUID)"
        label="$(blkid_field "${line}" LABEL)"
        if [ -n "${uuid}" ] && [ "${uuid,,}" = "${ident,,}" ]; then
            printf '%s\n' "${dev}"
            continue
        fi
        if [ -n "${label}" ] && [ "${label}" = "${ident}" ]; then
            printf '%s\n' "${dev}"
        fi
    done < <(blkid 2>/dev/null || true)
}

resolve_device() {
    local ident="${1}" matches=()
    if [ -b "${ident}" ]; then
        printf '%s' "${ident}"
        return 0
    fi
    if [ -b "/dev/${ident}" ]; then
        printf '/dev/%s' "${ident}"
        return 0
    fi
    mapfile -t matches < <(devices_matching "${ident}")
    if [ "${#matches[@]}" -ge 1 ]; then
        if [ "${#matches[@]}" -gt 1 ]; then
            warn "  '${ident}' matches ${#matches[@]} devices: ${matches[*]}"
            warn "  using ${matches[0]}: set localdisks to that disk's UUID to be explicit"
        fi
        printf '%s' "${matches[0]}"
        return 0
    fi
    return 1
}

# mount_disk <devnode> <fstype> <target>
mount_disk() {
    local dev="${1}" fstype="${2}" target="${3}"
    local opts="nosuid,nodev,relatime" mtype="${fstype}"

    case "${fstype}" in
        vfat | fat | msdos | exfat)
            # No POSIX permissions on these filesystems: map ownership instead.
            opts="${opts},uid=${PUID},gid=${PGID},umask=022"
            ;;
        ntfs)
            if grep -qw ntfs3 /proc/filesystems; then
                mtype="ntfs3"
                opts="${opts},uid=${PUID},gid=${PGID},umask=022"
            elif command -v ntfs-3g >/dev/null 2>&1; then
                info "  mounting NTFS through ntfs-3g (no ntfs3 kernel driver)"
                ntfs-3g -o "${opts},uid=${PUID},gid=${PGID},umask=022" \
                    "${dev}" "${target}"
                return $?
            else
                mtype="ntfs"
                opts="${opts},uid=${PUID},gid=${PGID},umask=022"
            fi
            ;;
        ext2 | ext3 | ext4 | xfs | btrfs | f2fs)
            ;;
        "")
            error "  the filesystem type could not be detected (no partition table?)"
            return 1
            ;;
        *)
            warn "  filesystem '${fstype}' is not in the supported list, trying a generic mount"
            mtype=""
            ;;
    esac

    if [ -n "${mtype}" ]; then
        mount -t "${mtype}" -o "${opts}" "${dev}" "${target}"
    else
        mount -o "${opts}" "${dev}" "${target}"
    fi
}

mount_one() {
    local entry="${1}" ident sub="" devnode name fstype target staging src

    if [ "${entry:0:1}" = "/" ]; then
        # "/dev/sda1" - a full device path, the whole filesystem is mounted
        ident="${entry}"
    else
        # "sda1" (whole disk) or "sda1/Media/Books" (one folder of that disk)
        ident="${entry%%/*}"
        if [ "${ident}" != "${entry}" ]; then
            sub="${entry#*/}"
            case "/${sub}/" in
                */../*) fatal "localdisks: '${entry}' must not contain '..'" ;;
            esac
        fi
    fi

    devnode="$(resolve_device "${ident}")" || devnode=""
    if [ -z "${devnode}" ]; then
        error "localdisks: '${entry}' matches no device, UUID or label visible in the container."
        error "The device node may not be handed to the container: the Supervisor only"
        error "passes the nodes declared in the app's 'devices' list. Add yours there, or"
        error "use the device name shown in the list above."
        return 1
    fi

    name="$(basename "${devnode}")"
    fstype="$(blkid -o value -s TYPE "${devnode}" 2>/dev/null || true)"

    if [ -n "${sub}" ]; then
        # Mount the whole disk out of sight, bind the requested folder, then drop
        # the whole-disk mount so the rest of that disk stays unreachable.
        target="/mnt/${name}/${sub}"
        staging="/mnt/.bindery-staging/${name}"
        if mountpoint -q "${target}" 2>/dev/null; then
            info "${target} is already mounted, nothing to do"
            return 0
        fi
        mkdir -p "${staging}"
        if ! mount_disk "${devnode}" "${fstype}" "${staging}"; then
            rmdir "${staging}" /mnt/.bindery-staging 2>/dev/null || true
            error "localdisks: ${devnode} could not be mounted"
            return 1
        fi
        src="$(readlink -f "${staging}/${sub}" || true)"
        if [ ! -d "${src}" ]; then
            umount -l "${staging}" || true
            error "localdisks: the folder '${sub}' does not exist on ${name} (case sensitive)"
            return 1
        fi
        if [[ "${src}" != "$(readlink -f "${staging}")"/* ]]; then
            umount -l "${staging}" || true
            error "localdisks: '${sub}' is a link pointing outside of ${name}"
            return 1
        fi
        mkdir -p "${target}"
        if ! mount --bind "${src}" "${target}"; then
            umount -l "${staging}" || true
            error "localdisks: ${src} could not be bound to ${target}"
            return 1
        fi
        umount -l "${staging}" || warn "  ${staging} is still mounted"
        rmdir "${staging}" /mnt/.bindery-staging 2>/dev/null || true
    else
        target="/mnt/${name}"
        if mountpoint -q "${target}" 2>/dev/null; then
            info "${target} is already mounted, nothing to do"
            return 0
        fi
        mkdir -p "${target}"
        if ! mount_disk "${devnode}" "${fstype}" "${target}"; then
            rmdir "${target}" 2>/dev/null || true
            error "localdisks: ${devnode} could not be mounted on ${target}"
            return 1
        fi
    fi

    info "${devnode} (${fstype:-unknown fs}) mounted at ${target}"
    return 0
}

mount_localdisks() {
    local entries=() entry
    mapfile -t entries < <(opt_list localdisks)

    if [ "${#entries[@]}" -eq 0 ]; then
        info "No localdisks configured: the app uses the Home Assistant folders only"
        return 0
    fi

    info "Disks visible in the container:"
    list_available_disks
    info "Mounting the disks listed in 'localdisks':"

    for entry in "${entries[@]}"; do
        entry="$(printf '%s' "${entry}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "${entry}" ] || continue
        if ! mount_one "${entry}"; then
            fatal "The app cannot start without its disk: fix 'localdisks' or remove the entry"
        fi
    done
    return 0
}

mount_localdisks

# ------------------------------------------------------------------------------
# 4. Folders
# ------------------------------------------------------------------------------
ensure_dir() {
    local path="${1}" label="${2}"

    case "${path}" in
        /mnt/*)
            if ! path_on_mount "${path}"; then
                error "${label} '${path}' is not inside a mounted disk."
                error "The path must sit under a disk listed in 'localdisks'. If you mounted"
                error "only one folder of a disk (e.g. 'sda1/Media/Books'), the path has to be"
                error "inside that folder. Writing outside a mount would lose data on restart,"
                error "so the app refuses to start."
                exit 1
            fi
            ;;
        /media | /media/* | /share | /share/* | /data | /data/*) ;;
        *)
            warn "${label} '${path}' is outside /media, /share, /mnt and /data: it will not survive a restart of the app"
            ;;
    esac

    if [ ! -d "${path}" ]; then
        mkdir -p "${path}" || fatal "${label} '${path}' could not be created"
        info "Created ${label} ${path}"
    fi
}

ensure_dir "${DATA_DIR}" "data folder"
mkdir -p "${DATA_DIR}/backups"
ensure_dir "${LIBRARY_DIR}" "library"
ensure_dir "${DOWNLOADS_DIR}" "downloads"
if [ -n "${AUDIOBOOKS_DIR}" ]; then
    ensure_dir "${AUDIOBOOKS_DIR}" "audiobook library"
fi
if [ -n "${AUDIOBOOK_DOWNLOADS_DIR}" ]; then
    ensure_dir "${AUDIOBOOK_DOWNLOADS_DIR}" "audiobook downloads"
fi

# ------------------------------------------------------------------------------
# 4b. Hardlinks
# ------------------------------------------------------------------------------
# Bindery hardlinks an import when source and destination are on the same
# filesystem, and copies otherwise (double disk usage). Two separate mounts have
# different device IDs even when they point at the same physical disk, so say it
# out loud instead of letting the user discover it in the Bindery log.
if [ -d "${LIBRARY_DIR}" ] && [ -d "${DOWNLOADS_DIR}" ]; then
    lib_dev="$(stat -c %d "${LIBRARY_DIR}" 2>/dev/null || echo lib)"
    dl_dev="$(stat -c %d "${DOWNLOADS_DIR}" 2>/dev/null || echo dl)"
    if [ "${lib_dev}" != "${dl_dev}" ]; then
        warn "library (${LIBRARY_DIR}) and downloads (${DOWNLOADS_DIR}) are on two different filesystems."
        warn "Bindery will copy imports instead of hardlinking them, which uses twice the disk space."
        warn "Mount the whole disk once (e.g. 'sda1') and use two folders of it to get hardlinks."
    else
        info "Hardlinks available: library and downloads are on the same filesystem"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Ownership
# ------------------------------------------------------------------------------
# Only the app's own data folder is chowned: the library and the download folder
# may be shared with other apps, and recursively changing their owner is not
# this app's call to make.
if [ "${PUID}" != "0" ] || [ "${PGID}" != "0" ]; then
    info "Giving ${DATA_DIR} to ${PUID}:${PGID}"
    chown -R "${PUID}:${PGID}" "${DATA_DIR}"

    for path in "${LIBRARY_DIR}" "${DOWNLOADS_DIR}" ${AUDIOBOOKS_DIR:+"${AUDIOBOOKS_DIR}"} ${AUDIOBOOK_DOWNLOADS_DIR:+"${AUDIOBOOK_DOWNLOADS_DIR}"}; do
        if ! s6-setuidgid "${PUID}:${PGID}" test -w "${path}" 2>/dev/null; then
            warn "${path} is not writable by ${PUID}:${PGID}."
            warn "Either give it the same owner (chown ${PUID}:${PGID} in a terminal) or keep PUID/PGID identical across the apps that share this folder."
        fi
    done
fi

info "Preparation finished: library=${LIBRARY_DIR} downloads=${DOWNLOADS_DIR} data=${DATA_DIR}"
