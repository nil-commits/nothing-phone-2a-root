#!/usr/bin/env bash
#
# restore.sh - unroot a Nothing Phone (2a) and optionally relock the bootloader.
#
# Restores a stock init_boot image (removing Magisk root). Relocking is optional
# and additionaly wipes the device.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

OTA=""
INIT_BOOT=""
RELOCK=0
ASSUME_YES=0

usage() {
  cat <<EOF
Usage: $(basename "$0") (--ota PATH_OR_URL | --init-boot FILE) [--relock] [--yes]

Removes root by flashing the stock init_boot image.

Image source (choose one):
  --ota PATH_OR_URL   Full OTA zip or URL (stock init_boot extracted automatically)
  --init-boot FILE    Stock init_boot.img matching your build

Options:
  --relock    After unrooting, relock the bootloader (WIPES DATA, needs full stock)
  --yes       Skip the flash confirmation
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ota)       OTA="${2:?--ota needs a value}"; shift 2 ;;
    --init-boot) INIT_BOOT="${2:?--init-boot needs a value}"; shift 2 ;;
    --relock)    RELOCK=1; shift ;;
    --yes)       ASSUME_YES=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "Unknown option: $1" ;;
  esac
done

sources=0
if [[ -n "$OTA" ]]; then sources=$((sources + 1)); fi
if [[ -n "$INIT_BOOT" ]]; then sources=$((sources + 1)); fi
if [[ "$sources" -eq 0 ]]; then
  usage
  die "Provide --ota or --init-boot."
fi
if [[ "$sources" -gt 1 ]]; then
  die "Provide only one image source."
fi

flash_init_boot() {
  local img="$1" slot
  slot="$(fastboot getvar current-slot 2>&1 | sed -n 's/^current-slot:[[:space:]]*//p' | tr -d '\r')"
  if [[ -n "$slot" ]] && fastboot flash "init_boot_${slot}" "$img" 2>/dev/null; then
    return 0
  fi
  fastboot flash init_boot "$img"
}

banner "Nothing Phone (2a) unroot / restore"

require_adb_device
check_is_np2a
mkdir -p "$NP2A_WORK"

if [[ -n "$INIT_BOOT" ]]; then
  [[ -f "$INIT_BOOT" ]] || die "init_boot image not found: $INIT_BOOT"
  STOCK="$INIT_BOOT"
else
  OTA_LOCAL="$OTA"
  if [[ "$OTA" =~ ^https?:// ]]; then
    require_cmd curl
    OTA_LOCAL="$NP2A_WORK/$(basename "${OTA%%\?*}")"
    [[ -f "$OTA_LOCAL" ]] || { info "Downloading OTA..."; curl -fL --progress-bar "$OTA" -o "$OTA_LOCAL"; }
  fi
  STOCK="$(extract_from_ota "$OTA_LOCAL" init_boot "$NP2A_WORK/stock")"
fi
ok "Stock init_boot: $STOCK"

if [[ "$ASSUME_YES" != 1 ]]; then
  confirm "Flash the stock image to remove root?" || die "Aborted."
fi

reboot_to_fastboot
flash_init_boot "$STOCK"
ok "Stock image flashed."
fastboot reboot
wait_for_android 300 || true

ok "Root removed. Open the Magisk app and uninstall it if you no longer need it."

if [[ "$RELOCK" == 1 ]]; then
  echo
  warn "Relocking will ERASE ALL DATA again and requires the device to be fully stock"
  warn "(stock boot images on both slots, no custom recovery). If anything is not"
  warn "stock, the device may refuse to boot after locking."
  if [[ "$ASSUME_YES" != 1 ]]; then
    confirm_typed "RELOCK" "Type RELOCK to wipe and lock the bootloader" || die "Skipped relocking."
  fi
  reboot_to_fastboot
  fastboot flashing lock || die "Failed to lock the bootloader."
  info "Rebooting..."
  fastboot reboot
  wait_for_android 600 || true
  ok "Bootloader locked. Note: OEM unlocking must stay enabled until you are sure the phone boots."
fi
