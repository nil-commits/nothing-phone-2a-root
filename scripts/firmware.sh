#!/usr/bin/env bash
#
# firmware.sh - fetch a stock partition image for your exact Nothing OS build
# from the community archive (spike0en/nothing_archive) and verify it by SHA-256.
#
# This removes the hardest part of rooting: finding and trusting the right
# stock image. Defaults to init_boot.img for the connected device's build.

# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUILD=""
CODENAME=""
TAG=""
PARTITION="init_boot"
OUT=""
LIST=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads the stock <partition>.img matching a Nothing OS build from the
community archive and verifies its SHA-256 against the published manifest.

Options:
  --build BUILD       Build number (default: read from the connected phone)
  --codename NAME     Device codename, e.g. Pacman (default: read from phone)
  --tag TAG           Use an explicit release tag (overrides --build/--codename)
  --partition NAME    Partition to fetch (default: init_boot)
  --out DIR           Output directory (default: .work/firmware)
  --list              List available builds for the device/codename and exit
  -h, --help          Show this help

Examples:
  ./firmware.sh                 # fetch init_boot.img for the connected phone
  ./firmware.sh --partition boot
  ./firmware.sh --list
  ./firmware.sh --build B4.1-260813-0941 --codename Pacman
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)     BUILD="${2:?--build needs a value}"; shift 2 ;;
    --codename)  CODENAME="${2:?--codename needs a value}"; shift 2 ;;
    --tag)       TAG="${2:?--tag needs a value}"; shift 2 ;;
    --partition) PARTITION="${2:?--partition needs a value}"; shift 2 ;;
    --out)       OUT="${2:?--out needs a value}"; shift 2 ;;
    --list)      LIST=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "Unknown option: $1" ;;
  esac
done

require_cmd curl sha256sum

# Resolve codename (archive CamelCase) from the phone if not supplied.
if [[ -z "$CODENAME" ]]; then
  require_adb_device
  check_is_np2a
  CODENAME="$(archive_codename "$(device_codename)")"
  [[ -n "$CODENAME" ]] || die "No archive mapping for device codename '$(device_codename)'."
fi

if [[ "$LIST" == 1 ]]; then
  banner "Available builds for $CODENAME"
  archive_list_tags "$CODENAME" | sed 's/^/  /'
  exit 0
fi

if [[ -z "$TAG" ]]; then
  if [[ -z "$BUILD" ]]; then
    require_adb_device
    check_is_np2a
    BUILD="$(device_build)"
  fi
  TAG="${CODENAME}_${BUILD}"
fi

if [[ -z "$OUT" ]]; then
  OUT="$NP2A_WORK/firmware/$TAG"
fi

banner "Fetching $PARTITION for $TAG"

if ! archive_release_exists "$TAG"; then
  err "No archive release tagged '$TAG'."
  err "Available builds:"
  archive_list_tags "$CODENAME" | sed 's/^/    /' >&2
  die "Pick one with --build, or supply an OTA/--init-boot instead."
fi

IMG="$(archive_fetch_partition "$TAG" "$PARTITION" "$OUT")"

echo
ok "Stock image ready: $IMG"
