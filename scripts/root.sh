#!/usr/bin/env bash
#
# root.sh - root a Nothing Phone (2a) with Magisk.
#
# Requires an unlocked bootloader (run unlock.sh first) and a stock
# init_boot.img that matches your exact build, or a full OTA zip/URL from
# which it can be extracted. See docs/FIRMWARE.md.

# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

INIT_BOOT=""
PATCHED=""
OTA=""
MAGISK_APK=""

usage() {
  cat <<EOF
Usage: $(basename "$0") (--ota PATH_OR_URL | --init-boot FILE | --patched FILE) [options]

Roots the phone by flashing a Magisk-patched init_boot image.

Image source (choose one):
  --ota PATH_OR_URL   Full OTA zip (local path or https URL). init_boot.img is
                      extracted automatically with payload-dumper-go.
  --init-boot FILE    A stock init_boot.img matching your build. It will be
                      patched on the phone by the Magisk app.
  --patched FILE      A ready Magisk-patched image (skips on-device patching).

Options:
  --magisk APK        Use this Magisk APK instead of downloading the latest
  -h, --help          Show this help

Examples:
  ./root.sh --ota ~/Downloads/Nothing_Phone_2a_OTA.zip
  ./root.sh --ota https://example.com/full-ota.zip
  ./root.sh --patched magisk_patched-27000_abcde.img
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ota)        OTA="${2:?--ota needs a value}"; shift 2 ;;
    --init-boot)  INIT_BOOT="${2:?--init-boot needs a value}"; shift 2 ;;
    --patched)    PATCHED="${2:?--patched needs a value}"; shift 2 ;;
    --magisk)     MAGISK_APK="${2:?--magisk needs a value}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "Unknown option: $1" ;;
  esac
done

sources=0
if [[ -n "$OTA" ]]; then sources=$((sources + 1)); fi
if [[ -n "$INIT_BOOT" ]]; then sources=$((sources + 1)); fi
if [[ -n "$PATCHED" ]]; then sources=$((sources + 1)); fi
if [[ "$sources" -eq 0 ]]; then
  usage
  die "Provide --ota, --init-boot or --patched."
fi
if [[ "$sources" -gt 1 ]]; then
  die "Provide only one image source."
fi

# ---------------------------------------------------------------------------
# Helpers local to this script
# ---------------------------------------------------------------------------
magisk_installed() {
  adb shell pm list packages 2>/dev/null | tr -d '\r' | grep -q '^package:com.topjohnwu.magisk$'
}

ensure_magisk_apk() {
  if [[ -n "$MAGISK_APK" ]]; then
    [[ -f "$MAGISK_APK" ]] || die "Magisk APK not found: $MAGISK_APK"
    printf '%s\n' "$MAGISK_APK"
    return 0
  fi
  mkdir -p "$NP2A_TOOLS"
  local cached
  cached="$(find "$NP2A_TOOLS" -maxdepth 1 -name 'Magisk-*.apk' 2>/dev/null | head -n1 || true)"
  if [[ -n "$cached" ]]; then
    printf '%s\n' "$cached"
    return 0
  fi
  require_cmd curl
  info "Fetching the latest Magisk APK..." >&2
  local url
  url="$(curl -fsSL https://api.github.com/repos/topjohnwu/Magisk/releases/latest \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]*\.apk"' \
    | head -n1 | sed -E 's/.*"(https[^"]+)".*/\1/')"
  [[ -n "$url" ]] || die "Could not resolve the Magisk APK download URL."
  curl -fsSL "$url" -o "$NP2A_TOOLS/Magisk.apk"
  printf '%s\n' "$NP2A_TOOLS/Magisk.apk"
}

# Flash the image to the active A/B slot's init_boot, falling back to init_boot.
flash_init_boot() {
  local img="$1" slot
  slot="$(fastboot getvar current-slot 2>&1 | sed -n 's/^current-slot:[[:space:]]*//p' | tr -d '\r')"
  if [[ -n "$slot" ]]; then
    info "Active slot: $slot"
    if fastboot flash "init_boot_${slot}" "$img" 2>/dev/null; then
      return 0
    fi
    warn "Flashing init_boot_${slot} failed; falling back to plain 'init_boot'."
  fi
  fastboot flash init_boot "$img"
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
banner "Nothing Phone (2a) root (Magisk)"

require_adb_device
check_is_np2a

if ! bootloader_unlocked; then
  die "Bootloader is locked. Run scripts/unlock.sh first (this wipes the device)."
fi
ok "Bootloader is unlocked."

BUILD="$(device_build)"
info "Device : $(device_model) ($(device_codename))"
info "Build  : $BUILD / Android $(device_android)"
warn "The image you flash MUST match this build ($BUILD). A mismatched image can bootloop the phone."
echo

mkdir -p "$NP2A_WORK"

# ---------------------------------------------------------------------------
# Obtain a Magisk-patched image
# ---------------------------------------------------------------------------
if [[ -n "$PATCHED" ]]; then
  [[ -f "$PATCHED" ]] || die "Patched image not found: $PATCHED"
  PATCHED_IMG="$PATCHED"
  ok "Using supplied patched image: $PATCHED_IMG"

else
  # Resolve a stock init_boot.img first.
  if [[ -n "$INIT_BOOT" ]]; then
    [[ -f "$INIT_BOOT" ]] || die "init_boot image not found: $INIT_BOOT"
    STOCK_INIT_BOOT="$INIT_BOOT"
  else
    OTA_LOCAL="$OTA"
    if [[ "$OTA" =~ ^https?:// ]]; then
      require_cmd curl
      OTA_LOCAL="$NP2A_WORK/$(basename "${OTA%%\?*}")"
      [[ -f "$OTA_LOCAL" ]] || { info "Downloading OTA (this can be several GB)..."; curl -fL --progress-bar "$OTA" -o "$OTA_LOCAL"; }
    fi
    [[ -f "$OTA_LOCAL" ]] || die "OTA not found: $OTA_LOCAL"
    STOCK_INIT_BOOT="$(extract_from_ota "$OTA_LOCAL" init_boot "$NP2A_WORK/stock")"
  fi
  ok "Stock init_boot: $STOCK_INIT_BOOT"

  # Make sure the Magisk app is present so it can patch the image.
  if ! magisk_installed; then
    warn "Magisk app is not installed on the phone."
    APK="$(ensure_magisk_apk)"
    info "Installing $(basename "$APK") ..."
    adb install -r "$APK"
  fi
  ok "Magisk app is installed."

  REMOTE_IMG="/sdcard/Download/init_boot.img"
  info "Pushing init_boot.img to $REMOTE_IMG ..."
  adb push "$STOCK_INIT_BOOT" "$REMOTE_IMG"

  echo
  banner "Patch the image on the phone"
  cat <<'STEPS'
On the phone:
  1. Open the Magisk app.
  2. Tap "Install" next to Magisk.
  3. Choose "Select and Patch a File".
  4. Select Download/init_boot.img (the file we just pushed).
  5. Wait until it reports "All done!" and shows an output file
     named magisk_patched-*.img in Downloads.
STEPS
  echo
  read -r -p "Press Enter here once Magisk says it is done... " _

  PATCHED_REMOTE="$(adb shell 'ls -t /sdcard/Download/magisk_patched-*.img 2>/dev/null | head -n1' | tr -d '\r')"
  [[ -n "$PATCHED_REMOTE" ]] || die "No magisk_patched-*.img found in Download. Did the patch finish?"

  PATCHED_IMG="$NP2A_WORK/$(basename "$PATCHED_REMOTE")"
  info "Pulling $PATCHED_REMOTE ..."
  adb pull "$PATCHED_REMOTE" "$PATCHED_IMG" >/dev/null
  ok "Patched image: $PATCHED_IMG"
fi

# ---------------------------------------------------------------------------
# Flash and reboot
# ---------------------------------------------------------------------------
echo
warn "About to flash the patched image to init_boot and reboot."
confirm "Flash now?" || die "Aborted before flashing."

reboot_to_fastboot
flash_init_boot "$PATCHED_IMG"
ok "Flashed."

info "Rebooting..."
fastboot reboot
wait_for_android 300 || true

echo
banner "Root steps finished"
info "Open the Magisk app and check that it reports an installed version."
info "If it shows 'Installed: N/A', re-open the app after a reboot."
echo
warn "Do not relock the bootloader while rooted: it will refuse to boot."
info "To undo: scripts/restore.sh (unroot / restore stock)."
