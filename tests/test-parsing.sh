#!/usr/bin/env bash
# ==============================================================================
# Unit tests for the blkid line parser.
#
# Runs inside the app image, because that is where the helper and its `sed` live:
#   docker run --rm -v "$PWD/tests:/tests:ro" bindery-ha:test /tests/test-parsing.sh
#
# Regression: a real disk (/dev/sda1, LABEL="HA_MEDIA") was listed with its UUID
# but the app reported "matches no device". blkid prints PARTUUID after UUID, and
# a greedy `.*UUID=` matched inside "PARTUUID".
# ==============================================================================
set -uo pipefail

# shellcheck source=/dev/null
. /usr/lib/bindery/common.sh

PASS=0
FAIL=0

expect() { # expect <description> <expected> <actual>
    if [ "${2}" = "${3}" ]; then
        printf '  \033[32mPASS\033[0m %s\n' "${1}"
        PASS=$((PASS + 1))
    else
        printf '  \033[31mFAIL\033[0m %s (attendu: <%s>, obtenu: <%s>)\n' "${1}" "${2}" "${3}"
        FAIL=$((FAIL + 1))
    fi
}

# A real Home Assistant disk, exactly as blkid prints it.
LINE1='/dev/sda1: LABEL="HA_MEDIA" UUID="66ad9fe2-5738-406c-a8c1-3593f4c5a620" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="6f1a2b3c-01"'
expect "UUID d'un disque partitionné" "66ad9fe2-5738-406c-a8c1-3593f4c5a620" "$(blkid_field "${LINE1}" UUID)"
expect "LABEL d'un disque partitionné" "HA_MEDIA" "$(blkid_field "${LINE1}" LABEL)"

# A GPT disk whose partition label differs from the filesystem label.
LINE2='/dev/sdb1: PARTLABEL="gpt-root" PARTUUID="abcd-1234-01" UUID="aaaa-bbbb-cccc" TYPE="ext4" LABEL="Mes Livres"'
expect "LABEL n'est pas PARTLABEL" "Mes Livres" "$(blkid_field "${LINE2}" LABEL)"
expect "UUID n'est pas PARTUUID" "aaaa-bbbb-cccc" "$(blkid_field "${LINE2}" UUID)"

# No label at all, and the UUID first after the device name.
LINE3='/dev/nvme0n1p2: UUID="11112222-3333" TYPE="squashfs"'
expect "UUID en premier champ" "11112222-3333" "$(blkid_field "${LINE3}" UUID)"
expect "LABEL absent" "" "$(blkid_field "${LINE3}" LABEL)"

# A label containing spaces, which word splitting would break.
LINE4='/dev/sdc1: LABEL="My Book" UUID="9999-8888" TYPE="ext4"'
expect "LABEL avec espace" "My Book" "$(blkid_field "${LINE4}" LABEL)"

# A line with nothing useful must not invent a value.
expect "ligne vide" "" "$(blkid_field "" UUID)"

printf '\n== %d réussis, %d échoués\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
