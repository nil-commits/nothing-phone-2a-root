#!/usr/bin/env bash
#
# common.sh - shared helpers for the Nothing Phone (2a) rooting toolkit.
#
# This file is meant to be sourced, never executed:
#   source "$(dirname "$0")/common.sh"
#
# It intentionally has no side effects on source other than defining
# functions, colours and constants.

# shellcheck shell=bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours / logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'
  C_BLD=$'\033[1m'
else
  C_RESET=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_BLD=
fi

info() { printf '%s[*]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# ro.product.device for the Nothing Phone (2a). Pacman = 2a, PacmanPro = 2a Pro.
readonly NP2A_CODENAMES=(pacman pacmanpro)
readonly NP2A_PRETTY="Nothing Phone (2a)"

# Root of the repository (scripts/..).
NP2A_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NP2A_ROOT
readonly NP2A_TOOLS="$NP2A_ROOT/.tools"
readonly NP2A_WORK="$NP2A_ROOT/.work"

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 \
      || die "Required command '$c' not found. Install it (Arch/CachyOS: sudo pacman -S android-tools curl unzip)."
  done
}

confirm() {
  local prompt="${1:-Continue?}" reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Require the user to type an exact word. Guards destructive actions.
confirm_typed() {
  local word="$1" prompt="${2:-Type '$1' to continue}" reply
  read -r -p "$prompt: " reply
  [[ "$reply" == "$word" ]]
}

# ---------------------------------------------------------------------------
# ADB helpers
# ---------------------------------------------------------------------------
require_adb_device() {
  require_cmd adb
  adb start-server >/dev/null 2>&1 || true

  local state
  state="$(adb get-state 2>/dev/null || true)"
  case "$state" in
    device) : ;;
    unauthorized)
      die "Phone is 'unauthorized'. Unlock the screen and tap 'Allow' on the USB-debugging prompt." ;;
    *)
      die "No phone detected over ADB. Connect it, enable USB debugging, then authorize this computer." ;;
  esac
}

adb_serial() { adb get-serialno 2>/dev/null | tr -d '\r'; }

# Read a property from the device, stripping the trailing CR.
dev_prop() { adb shell getprop "$1" 2>/dev/null | tr -d '\r'; }

device_codename() { dev_prop ro.product.device; }
device_model()    { dev_prop ro.product.model; }
device_build()    { dev_prop ro.build.display.id; }
device_android()  { dev_prop ro.build.version.release; }

# The developer-options "OEM unlocking" toggle. Must be 1 to unlock.
oem_unlock_allowed() { [[ "$(dev_prop sys.oem_unlock_allowed)" == "1" ]]; }

# Verified boot state is "green" when locked, "orange" when unlocked.
bootloader_unlocked() { [[ "$(dev_prop ro.boot.verifiedbootstate)" == "orange" ]]; }

check_is_np2a() {
  local cn; cn="$(device_codename | tr '[:upper:]' '[:lower:]')"
  [[ -n "$cn" ]] || die "Could not read ro.product.device. Is the phone actually connected?"
  case " ${NP2A_CODENAMES[*]} " in
    *" $cn "*) ok "Detected $NP2A_PRETTY (codename: $cn)" ;;
    *) die "Unsupported device '$cn'. This toolkit targets the $NP2A_PRETTY (pacman/pacmanpro)." ;;
  esac
}

# ---------------------------------------------------------------------------
# Fastboot helpers
# ---------------------------------------------------------------------------
# Wait until a fastboot device shows up. $1 = timeout seconds (default 90).
wait_for_fastboot() {
  local timeout="${1:-90}" i
  require_cmd fastboot
  info "Waiting for a fastboot device (up to ${timeout}s)..."
  for ((i = 0; i < timeout; i++)); do
    if fastboot devices 2>/dev/null | grep -qw fastboot; then
      ok "Fastboot device ready."
      return 0
    fi
    sleep 1
  done
  die "Timed out waiting for fastboot. Check the cable/port and that the phone is in bootloader mode."
}

require_fastboot_device() {
  require_cmd fastboot
  fastboot devices 2>/dev/null | grep -qw fastboot \
    || die "No fastboot device. Run 'adb reboot bootloader' first (or hold Volume Down + Power)."
}

# Reboot the phone into the bootloader and wait for fastboot.
reboot_to_fastboot() {
  require_adb_device
  info "Rebooting to bootloader..."
  adb reboot bootloader
  # Give the device a moment to leave adb before polling fastboot.
  sleep 3
  wait_for_fastboot
}

# Wait for Android to come back over adb. $1 = timeout seconds (default 300).
wait_for_android() {
  local timeout="${1:-300}" i
  info "Waiting for Android to boot (up to ${timeout}s)..."
  for ((i = 0; i < timeout; i++)); do
    if [[ "$(adb get-state 2>/dev/null || true)" == "device" ]]; then
      ok "Android is up and ADB is authorized."
      return 0
    fi
    sleep 2
  done
  warn "Phone did not come back over ADB (it may need USB debugging re-authorized, or a longer first boot)."
  return 1
}

# ---------------------------------------------------------------------------
# Firmware / payload helpers
# ---------------------------------------------------------------------------
# Print path to a usable payload-dumper-go binary, downloading it if needed.
ensure_payload_dumper() {
  require_cmd curl tar
  mkdir -p "$NP2A_TOOLS"

  local existing
  existing="$(find "$NP2A_TOOLS" -maxdepth 3 -type f -name 'payload-dumper-go' -perm -u+x 2>/dev/null | head -n1 || true)"
  if [[ -n "$existing" ]]; then
    printf '%s\n' "$existing"
    return 0
  fi

  info "payload-dumper-go not found locally, fetching the latest release..." >&2
  local api="https://api.github.com/repos/ssut/payload-dumper-go/releases/latest"
  local json url
  json="$(curl -fsSL "$api")"
  # Prefer the portable linux_amd64 build; fall back to the avx2 variant.
  url="$(grep -oE '"browser_download_url":[[:space:]]*"[^"]*linux_amd64\.tar\.gz"' <<<"$json" \
    | head -n1 | sed -E 's/.*"(https[^"]+)".*/\1/')"
  if [[ -z "$url" ]]; then
    url="$(grep -oE '"browser_download_url":[[:space:]]*"[^"]*linux_amd64_avx2\.tar\.gz"' <<<"$json" \
      | head -n1 | sed -E 's/.*"(https[^"]+)".*/\1/')"
  fi

  [[ -n "$url" ]] || die "Could not resolve a payload-dumper-go release URL (offline? rate-limited?). Download it manually into $NP2A_TOOLS/."
  info "Downloading: $url" >&2

  local tmp="$NP2A_TOOLS/pdg-download"
  rm -rf "$tmp"; mkdir -p "$tmp"
  curl -fsSL "$url" -o "$tmp/pdg.tar.gz"
  tar -xzf "$tmp/pdg.tar.gz" -C "$tmp"
  rm -f "$tmp/pdg.tar.gz"

  local bin
  bin="$(find "$tmp" -type f -name 'payload-dumper-go' -perm -u+x | head -n1 || true)"
  [[ -n "$bin" ]] || die "payload-dumper-go binary not found inside the release archive."
  mv "$bin" "$NP2A_TOOLS/payload-dumper-go"
  chmod +x "$NP2A_TOOLS/payload-dumper-go"
  rm -rf "$tmp"

  printf '%s\n' "$NP2A_TOOLS/payload-dumper-go"
}

# Extract a specific image from a full OTA zip (or a raw payload.bin).
# Usage: extract_from_ota <ota.zip> <part-name> <out-dir>  -> echoes output path
extract_from_ota() {
  local ota="$1" part="$2" out="$3"
  [[ -f "$ota" ]] || die "OTA/payload file not found: $ota"
  require_cmd xz

  local pdg
  pdg="$(ensure_payload_dumper)"

  info "Dumping '$part' from $(basename "$ota") ..."
  local ddir="$out/dumped"
  mkdir -p "$ddir"
  # payload-dumper-go accepts a full OTA zip (detected by content) or payload.bin.
  if ! "$pdg" -o "$ddir" -p "$part" -q "$ota"; then
    die "Failed to dump '$part'. Is this a *full* OTA for the right device/build?"
  fi

  local result
  result="$(find "$ddir" -type f -name "${part}.img" | head -n1 || true)"
  [[ -n "$result" ]] || die "payload-dumper-go did not produce ${part}.img."
  printf '%s\n' "$result"
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
# Print a header banner.
banner() {
  printf '%s\n' "${C_BLD}==============================================================${C_RESET}"
  printf '%s\n' "${C_BLD} $*${C_RESET}"
  printf '%s\n' "${C_BLD}==============================================================${C_RESET}"
}

# Require internet reachability (best effort).
require_internet() {
  curl -fsSL --max-time 8 https://api.github.com/ >/dev/null 2>&1 \
    || die "No internet access. Some steps (downloading tools) require a connection."
}
