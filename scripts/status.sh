#!/usr/bin/env bash
#
# status.sh - show connection, device and lock/root status.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

banner "Nothing Phone (2a) status"
require_cmd adb

state="$(adb get-state 2>/dev/null || true)"

if [[ "$state" == "device" ]]; then
  require_adb_device
  check_is_np2a
  echo
  printf '%-18s %s\n' "Model:"        "$(device_model) ($(device_codename))"
  printf '%-18s %s\n' "Android:"      "$(device_android)"
  printf '%-18s %s\n' "Build:"        "$(device_build)"
  printf '%-18s %s\n' "Serial:"       "$(adb_serial)"

  if oem_unlock_allowed; then
    printf '%-18s %s\n' "OEM unlocking:" "enabled"
  else
    printf '%-18s %s\n' "OEM unlocking:" "DISABLED (enable in Developer options)"
  fi

  if bootloader_unlocked; then
    printf '%-18s %s\n' "Bootloader:" "unlocked"
  else
    printf '%-18s %s\n' "Bootloader:" "locked"
  fi

  if adb shell pm list packages 2>/dev/null | tr -d '\r' | grep -q '^package:com.topjohnwu.magisk$'; then
    printf '%-18s %s\n' "Magisk app:" "installed"
  else
    printf '%-18s %s\n' "Magisk app:" "not installed"
  fi

  if bootloader_unlocked && adb shell "su -c id" >/dev/null 2>&1; then
    printf '%-18s %s\n' "Root:" "working"
  elif bootloader_unlocked; then
    printf '%-18s %s\n' "Root:" "not granted over ADB (check the Magisk app)"
  fi

elif fastboot devices 2>/dev/null | grep -qw fastboot; then
  info "Device is in fastboot/bootloader mode."
  fastboot getvar unlocked 2>&1 | sed 's/^/    /' || true
  fastboot getvar current-slot 2>&1 | sed 's/^/    /' || true

else
  die "No device found over ADB or fastboot. Connect it and enable USB debugging."
fi
