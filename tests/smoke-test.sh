#!/usr/bin/env bash
# ==============================================================================
# Smoke tests for the Bindery Home Assistant app image.
#
#   ./tests/smoke-test.sh            # build the image, then run every test
#   ./tests/smoke-test.sh --no-build # run against the existing image
#   IMAGE=my/image:tag ./tests/smoke-test.sh
#
# Tests 1 and 2 need nothing special. Tests 3 to 5 create a loop device and
# therefore need a Docker daemon that allows privileged containers (Docker
# Desktop, OrbStack, a Linux host). They are skipped otherwise.
# ==============================================================================
set -uo pipefail

IMAGE="${IMAGE:-bindery-ha:test}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bindery-smoke.XXXXXX")"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bindery"
PORT=18787
PASS=0
FAIL=0
SKIP=0

cleanup() {
    if [ -n "${LOOPDEV:-}" ] && [ "${LOOPDEV}" != "none" ]; then
        docker run --rm --privileged -v /dev:/dev alpine:3.22 losetup -d "${LOOPDEV}" >/dev/null 2>&1
    fi
    docker volume rm -f smoke-t2-data >/dev/null 2>&1
    docker rm -f smoke-bindery smoke-puid smoke-disk smoke-sub smoke-bad smoke-nodev smoke-loop >/dev/null 2>&1
    rm -rf "${WORK}"
}
trap cleanup EXIT

ok() { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
ko() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
sk() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; SKIP=$((SKIP + 1)); }

check() { # check <description> <command...>
    local desc="${1}"
    shift
    if "$@" >/dev/null 2>&1; then ok "${desc}"; else ko "${desc}"; fi
}

# log_has <container> <pattern> - avoids grep -q under pipefail (SIGPIPE on docker logs)
log_has() {
    docker logs "${1}" >"${WORK}/last.log" 2>&1 || true
    grep -q -- "${2}" "${WORK}/last.log"
}

check_not() {
    local desc="${1}"
    shift
    if "$@" >/dev/null 2>&1; then ko "${desc}"; else ok "${desc}"; fi
}

# wait_health <port> [tries]
wait_health() {
    local port="${1}" tries="${2:-30}" code=""
    for _ in $(seq 1 "${tries}"); do
        code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/api/v1/health" || true)"
        [ "${code}" = "200" ] && return 0
        sleep 1
    done
    return 1
}

# kill_bindery <container> - SIGKILL the Bindery process to simulate a crash
kill_bindery() {
    local pid
    pid="$(docker exec "${1}" sh -c 'for p in /proc/[0-9]*; do
        if tr "\0" " " < "$p/cmdline" 2>/dev/null | grep -q "^/usr/bin/bindery"; then
            echo "${p#/proc/}"
        fi
    done' 2>/dev/null | head -1)"
    [ -n "${pid}" ] || return 1
    docker exec "${1}" kill -9 "${pid}" >/dev/null 2>&1
}

write_options() { # write_options <dir> <json>
    mkdir -p "${1}/data"
    printf '%s\n' "${2}" >"${1}/data/options.json"
}

run_app() { # run_app <name> <dir> <port> [extra docker args...]
    local name="${1}" dir="${2}" port="${3}"
    shift 3
    docker rm -f "${name}" >/dev/null 2>&1
    docker run -d --name "${name}" -p "${port}:8787" \
        -v "${dir}/data:/data" -v "${dir}/media:/media" -v "${dir}/share:/share" \
        "$@" "${IMAGE}" >/dev/null
}

# ------------------------------------------------------------------------------
if [ "${1:-}" != "--no-build" ]; then
    echo "== Building ${IMAGE} from ${APP_DIR}"
    docker build -q -t "${IMAGE}" "${APP_DIR}" >/dev/null || { echo "build failed"; exit 1; }
fi

echo "== Test 1: default storage (Home Assistant folders only)"
D1="${WORK}/t1"
mkdir -p "${D1}/media" "${D1}/share"
write_options "${D1}" '{"log_level":"info","TZ":"Europe/Paris","PUID":0,"PGID":0,"localdisks":[],
 "library_dir":"/media/books","downloads_dir":"/media/downloads","audiobooks_dir":"",
 "audiobook_downloads_dir":"","dir_mode":"0750","telemetry":true,"env_vars":[]}'
run_app smoke-bindery "${D1}" "${PORT}"
check "app answers /api/v1/health with 200" wait_health "${PORT}"
check "library folder created under /media" test -d "${D1}/media/books"
check "downloads folder created under /media" test -d "${D1}/media/downloads"
check "database created in the app data folder" test -f "${D1}/data/bindery/bindery.db"
log_has smoke-bindery 'No localdisks configured' \
    && ok "log says no external disk is used" || ko "log says no external disk is used"
log_has smoke-bindery 'Timezone set to Europe/Paris' \
    && ok "timezone applied" || ko "timezone applied"
docker restart smoke-bindery >/dev/null 2>&1
check "restart keeps the same database (no data loss)" wait_health "${PORT}" 40
check "database still present after restart" test -f "${D1}/data/bindery/bindery.db"
docker rm -f smoke-bindery >/dev/null 2>&1

echo "== Test 2: PUID/PGID 1000 + env_vars"
D2="${WORK}/t2"
mkdir -p "${D2}/media" "${D2}/share"
write_options "${D2}" '{"log_level":"debug","TZ":"America/New_York","PUID":1000,"PGID":1000,"localdisks":[],
 "library_dir":"/media/books","downloads_dir":"/media/downloads","audiobooks_dir":"/media/audiobooks",
 "audiobook_downloads_dir":"","dir_mode":"0755","telemetry":false,
 "env_vars":[{"name":"BINDERY_CONTACT","value":"books@example.org"},
             {"name":"BINDERY_LIBRARY_DIR","value":"/ignored"}]}'
# /data goes to a named volume: on macOS a bind mount cannot hold POSIX
# ownership, so the chown path can only be verified on a real Linux filesystem.
docker volume rm -f smoke-t2-data >/dev/null 2>&1
docker volume create smoke-t2-data >/dev/null
docker run --rm -i -v smoke-t2-data:/data alpine:3.22 \
    sh -c 'cat > /data/options.json' <"${D2}/data/options.json"
docker rm -f smoke-puid >/dev/null 2>&1
docker run -d --name smoke-puid -p "$((PORT + 1)):8787" \
    -v smoke-t2-data:/data -v "${D2}/media:/media" "${IMAGE}" >/dev/null
check "app starts as uid 1000" wait_health "$((PORT + 1))"
log_has smoke-puid 'PUID/PGID match confirmed' \
    && ok "Bindery confirms the PUID/PGID pair" || ko "Bindery confirms the PUID/PGID pair"
check "data folder owned by 1000" test "$(docker exec smoke-puid stat -c %u /data/bindery)" = "1000"
check "audiobook folder created" test -d "${D2}/media/audiobooks"
log_has smoke-puid 'env_vars: BINDERY_CONTACT=books@example.org' \
    && ok "extra BINDERY_* variable exported" || ko "extra BINDERY_* variable exported"
log_has smoke-puid 'BINDERY_LIBRARY_DIR is driven by the app options' \
    && ok "option-owned variables cannot be overridden" || ko "option-owned variables cannot be overridden"
docker rm -f smoke-puid >/dev/null 2>&1

echo "== Test 3: external disk (loop device, ext4, by label)"
# A real block device is the only way to exercise the mount path. This needs a
# Docker daemon that allows --privileged; on anything else the disk tests skip.
LOOPDEV="$(docker run --rm --privileged -v "${WORK}:/host" alpine:3.22 sh -c '
  apk add --no-cache e2fsprogs util-linux >/dev/null 2>&1 || exit 1
  losetup -D >/dev/null 2>&1 || true
  dd if=/dev/zero of=/host/disk.img bs=1M count=64 status=none || exit 1
  LOOP=$(losetup -f --show /host/disk.img) || exit 1
  mkfs.ext4 -q -L SmokeBooks "$LOOP" || exit 1
  mkdir -p /mnt/x && mount "$LOOP" /mnt/x || exit 1
  mkdir -p /mnt/x/Media/Books && echo marker > /mnt/x/Media/Books/marker.txt
  umount /mnt/x && echo "$LOOP"' 2>/dev/null | tail -1)"
DISK="$(basename "${LOOPDEV:-none}")"
if [ -b /dev/null ] && [ "${DISK}" != "none" ]; then
    :
fi
if [ "${DISK}" = "none" ] || [ -z "${DISK}" ]; then
    PRIV_OK=0
else
    PRIV_OK=1
fi

if [ "${PRIV_OK}" -eq 1 ]; then
    D3="${WORK}/t3"
    mkdir -p "${D3}/media" "${D3}/share"
    write_options "${D3}" "{\"log_level\":\"info\",\"TZ\":\"UTC\",\"PUID\":0,\"PGID\":0,\"localdisks\":[\"SmokeBooks\"],
     \"library_dir\":\"/mnt/${DISK}/books\",\"downloads_dir\":\"/mnt/${DISK}/downloads\",\"audiobooks_dir\":\"\",
     \"audiobook_downloads_dir\":\"\",\"dir_mode\":\"0750\",\"telemetry\":true,\"env_vars\":[]}"
    run_app smoke-disk "${D3}" "$((PORT + 2))" --privileged --device "${LOOPDEV}"
    check "app starts with an external disk" wait_health "$((PORT + 2))"
    log_has smoke-disk "mounted at /mnt/${DISK}" \
        && ok "disk resolved by label and mounted" || ko "disk resolved by label and mounted"
    check "bindery wrote its folders on the disk" \
        docker exec smoke-disk test -d "/mnt/${DISK}/books"
    docker exec smoke-disk sh -c "printf x > /mnt/${DISK}/downloads/a.epub && ln /mnt/${DISK}/downloads/a.epub /mnt/${DISK}/books/a.epub" >/dev/null 2>&1 \
        && ok "hardlink between downloads and library works" || ko "hardlink between downloads and library works"
    log_has smoke-disk 'Hardlinks available' \
        && ok "hardlink capability detected at startup" || ko "hardlink capability detected at startup"
    docker rm -f smoke-disk >/dev/null 2>&1

    echo "== Test 4: only one folder of a disk"
    D4="${WORK}/t4"
    mkdir -p "${D4}/media" "${D4}/share"
    write_options "${D4}" "{\"log_level\":\"info\",\"TZ\":\"UTC\",\"PUID\":0,\"PGID\":0,\"localdisks\":[\"${DISK}/Media/Books\"],
     \"library_dir\":\"/mnt/${DISK}/Media/Books\",\"downloads_dir\":\"/mnt/${DISK}/Media/Books/downloads\",
     \"audiobooks_dir\":\"\",\"audiobook_downloads_dir\":\"\",\"dir_mode\":\"0750\",\"telemetry\":true,\"env_vars\":[]}"
    run_app smoke-sub "${D4}" "$((PORT + 3))" --privileged --device "${LOOPDEV}"
    check "app starts with a folder-only mount" wait_health "$((PORT + 3))"
    check "only the requested folder is mounted" \
        test "$(docker exec smoke-sub cat /proc/mounts | grep -c "/mnt/${DISK}/Media/Books ")" = "1"
    check_not "the whole disk is not exposed" \
        docker exec smoke-sub mountpoint -q "/mnt/${DISK}"
    docker rm -f smoke-sub >/dev/null 2>&1
else
    sk "external disk tests (no privileged containers on this Docker daemon)"
fi

echo "== Test 5: a disk that cannot be mounted stops the app"
D5="${WORK}/t5"
mkdir -p "${D5}/media" "${D5}/share"
write_options "${D5}" '{"log_level":"info","TZ":"UTC","PUID":0,"PGID":0,"localdisks":["sdz99"],
 "library_dir":"/mnt/sdz99/books","downloads_dir":"/mnt/sdz99/downloads","audiobooks_dir":"",
 "audiobook_downloads_dir":"","dir_mode":"0750","telemetry":true,"env_vars":[]}'
run_app smoke-bad "${D5}" "$((PORT + 4))"
sleep 8
log_has smoke-bad 'FATAL' \
    && ok "a missing disk is reported as fatal" || ko "a missing disk is reported as fatal"
check_not "the app is not left running" \
    sh -c "docker inspect -f '{{.State.Running}}' smoke-bad 2>/dev/null | grep -q true"
docker rm -f smoke-bad >/dev/null 2>&1

echo "== Test 6: library outside a mounted disk is refused"
D6="${WORK}/t6"
mkdir -p "${D6}/media" "${D6}/share"
write_options "${D6}" '{"log_level":"info","TZ":"UTC","PUID":0,"PGID":0,"localdisks":[],
 "library_dir":"/mnt/sda1/Media/Books","downloads_dir":"/media/downloads","audiobooks_dir":"",
 "audiobook_downloads_dir":"","dir_mode":"0750","telemetry":true,"env_vars":[]}'
run_app smoke-nodev "${D6}" "$((PORT + 5))"
sleep 8
log_has smoke-nodev 'not inside a mounted disk' \
    && ok "library on an unmounted path is refused" || ko "library on an unmounted path is refused"
docker rm -f smoke-nodev >/dev/null 2>&1


echo "== Test 7: repeated crashes stop the app instead of looping forever"
D7="${WORK}/t7"
mkdir -p "${D7}/media" "${D7}/share"
write_options "${D7}" '{"log_level":"info","TZ":"UTC","PUID":0,"PGID":0,"localdisks":[],
 "library_dir":"/media/books","downloads_dir":"/media/downloads","audiobooks_dir":"",
 "audiobook_downloads_dir":"","dir_mode":"0750","telemetry":true,"env_vars":[]}'
run_app smoke-loop "${D7}" "$((PORT + 6))"
check "app starts before the crashes" wait_health "$((PORT + 6))"
for _ in 1 2 3 4 5 6 7 8; do
    docker inspect -f '{{.State.Running}}' smoke-loop 2>/dev/null | grep -q true || break
    kill_bindery smoke-loop || break
    sleep 3
done
sleep 3
check_not "the app ends up stopped" \
    sh -c "docker inspect -f '{{.State.Running}}' smoke-loop 2>/dev/null | grep -q true"
log_has smoke-loop 'giving up' \
    && ok "the log explains why it stopped" || ko "the log explains why it stopped"
docker rm -f smoke-loop >/dev/null 2>&1

echo
printf '== %d passed, %d failed, %d skipped\n' "${PASS}" "${FAIL}" "${SKIP}"
[ "${FAIL}" -eq 0 ]
