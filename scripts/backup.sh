#!/usr/bin/env bash
#
# backup.sh - pull your personal files off the Nothing Phone (2a) over ADB.
#
# Run this BEFORE unlocking the bootloader, because unlocking wipes the device.
#
# Only files readable without root are backed up: everything under /sdcard
# (media, documents, downloads, app exports) plus Android/media. App-private
# data (chat history, etc.) is NOT reachable over plain ADB; export it from
# inside the relevant apps first. See docs/BACKUP.md.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DEST=""
CHECKSUMS=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Pulls personal files from the phone into a timestamped folder.

Options:
  --dest DIR        Destination directory (default: \$HOME/Nothing2a-Backup-<timestamp>)
  --no-checksums    Skip generating SHA-256 checksums
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)         DEST="${2:?--dest needs a value}"; shift 2 ;;
    --no-checksums) CHECKSUMS=0; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "Unknown option: $1" ;;
  esac
done

# Directories under /sdcard worth copying. Missing ones are skipped quietly.
DIRS=(
  DCIM
  Pictures
  Movies
  Download
  Documents
  Music
  Recordings
  Podcasts
  Audiobooks
  Alarms
  Notifications
  Ringtones
  Android/media
)

banner "Nothing Phone (2a) backup"

require_adb_device
check_is_np2a

if [[ -z "$DEST" ]]; then
  DEST="$HOME/Nothing2a-Backup-$(date +%Y%m%d-%H%M%S)"
fi
[[ "$DEST" == /* ]] || DEST="$PWD/$DEST"
mkdir -p "$DEST"

info "Device : $(device_model) ($(device_codename))"
info "Build  : $(device_build) / Android $(device_android)"
info "Target : $DEST"
echo

TOTAL_START=$(date +%s)

for d in "${DIRS[@]}"; do
  if ! adb shell "[ -e /sdcard/$d ]" >/dev/null 2>&1; then
    continue
  fi
  info "Copying /sdcard/$d ..."
  mkdir -p "$DEST/$(dirname "$d")"
  if adb pull -a "/sdcard/$d" "$DEST/$d/" >/dev/null 2>&1; then
    ok "  $d"
  else
    warn "  Failed to fully copy $d (continuing)."
  fi
done

# Loose exports that often sit directly in /sdcard (contacts .vcf, SMS .xml, ...).
info "Copying loose files in /sdcard root (exports, etc.) ..."
LOOSE="$(adb shell 'ls /sdcard/*.vcf /sdcard/*.xml /sdcard/*.csv 2>/dev/null' | tr -d '\r' || true)"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  adb pull -a "$f" "$DEST/" >/dev/null 2>&1 && ok "  $(basename "$f")" || warn "  Failed: $f"
done <<< "$LOOSE"

TOTAL_END=$(date +%s)
SIZE="$(du -sh "$DEST" 2>/dev/null | cut -f1)"
FILES="$(find "$DEST" -type f 2>/dev/null | wc -l)"

# Manifest describing exactly what this backup is.
{
  echo "Nothing Phone (2a) backup manifest"
  echo "date        : $(date -Is)"
  echo "model       : $(device_model)"
  echo "codename    : $(device_codename)"
  echo "build       : $(device_build)"
  echo "android     : $(device_android)"
  echo "serial      : $(adb_serial)"
  echo "dest        : $DEST"
  echo "files       : $FILES"
  echo "size        : $SIZE"
  echo "root        : no (sdcard-only pull)"
} > "$DEST/BACKUP-MANIFEST.txt"

if [[ "$CHECKSUMS" == 1 ]]; then
  info "Generating SHA-256 checksums ..."
  ( cd "$DEST" && find . -type f ! -name 'BACKUP-MANIFEST.txt' ! -name 'SHA256SUMS.txt' -print0 \
      | sort -z | xargs -0 -r sha256sum > SHA256SUMS.txt )
  ok "Wrote $DEST/SHA256SUMS.txt"
fi

echo
banner "Backup complete"
info "Files : $FILES"
info "Size  : $SIZE"
info "Took  : $((TOTAL_END - TOTAL_START))s"
info "Path  : $DEST"
echo
warn "This backup covers /sdcard only. Chat histories and app-private data must be"
warn "exported from within each app (e.g. WhatsApp -> Chats -> Back up; Contacts -> Export .vcf)."
