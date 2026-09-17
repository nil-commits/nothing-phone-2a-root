#!/usr/bin/env bash
#
# unlock.sh - unlock the bootloader of a Nothing Phone (2a).
#
# WARNING: unlocking the bootloader triggers a mandatory factory reset.
# Everything on the device is erased and cannot be recovered. Back up first
# with backup.sh.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--yes]

Unlocks the bootloader. Requires Developer options -> "OEM unlocking" to be
enabled and the phone connected with USB debugging authorized.

Options:
  --yes    Skip the interactive confirmation (for automation; dangerous)
  -h, --help
EOF
}

ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)     ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1" ;;
  esac
done

banner "Nothing Phone (2a) bootloader unlock"

require_adb_device
check_is_np2a

if bootloader_unlocked; then
  ok "Bootloader already looks unlocked (verified boot state: orange). Nothing to do."
  exit 0
fi

if ! oem_unlock_allowed; then
  err "Developer options -> 'OEM unlocking' is OFF (or greyed out)."
  err "Enable it on the phone (connect to the internet if it is greyed out), then retry."
  exit 1
fi

info "Device : $(device_model) ($(device_codename))"
info "Build  : $(device_build) / Android $(device_android)"
echo

warn "This will ERASE ALL DATA on the phone (factory reset)."
warn "Photos, apps, accounts and internal storage will be gone."
warn "There is no way to undo this without losing data."
echo
warn "Have you run backup.sh first?"
echo

if [[ "$ASSUME_YES" != 1 ]]; then
  confirm_typed "UNLOCK" "Type UNLOCK to erase the phone and unlock its bootloader" \
    || die "Aborted. Nothing was changed."
fi

reboot_to_fastboot

info "Current lock state:"
fastboot getvar unlocked 2>&1 | sed 's/^/    /' || true
echo

info "Sending unlock command..."
if ! fastboot flashing unlock; then
  warn "'fastboot flashing unlock' failed; trying the legacy 'fastboot oem unlock'..."
  fastboot oem unlock || die "Both unlock commands failed. Is OEM unlocking really enabled?"
fi

echo
banner "Confirm ON THE PHONE"
warn "Look at the phone screen. A warning about unlocking will be shown."
warn "Use Volume Up/Down to highlight 'Unlock the bootloader', then press Power to confirm."
warn "The device will then erase all data and reboot. This can take several minutes."

# The unlock return value does not tell us whether the user confirmed on-device.
# Wait for the device to settle. A factory reset means USB debugging will be off
# afterwards, so a failure to find ADB again is expected rather than fatal.
wait_for_android 600 || true

echo
banner "Unlock command sent"
info "If the phone booted into the setup wizard, the unlock was accepted."
info "After setup: re-enable Developer options -> USB debugging, then run:"
info "  scripts/status.sh          # confirm 'Bootloader: unlocked'"
info "  scripts/root.sh --ota ...  # install Magisk"
echo
warn "Keep 'OEM unlocking' enabled. Turning it off can make the device refuse to boot."
