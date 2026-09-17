#!/usr/bin/env bash
#
# np2a - entry point for the Nothing Phone (2a) rooting toolkit.
#
#   ./np2a.sh status
#   ./np2a.sh backup
#   ./np2a.sh unlock
#   ./np2a.sh root --ota ~/Downloads/full-ota.zip
#   ./np2a.sh restore --init-boot stock_init_boot.img [--relock]

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Nothing Phone (2a) rooting toolkit

Usage: ./np2a.sh <command> [options]

Commands:
  status            Show connection, build and lock/root status
  backup            Pull personal files off the phone (do this first!)
  unlock            Unlock the bootloader (factory-resets the phone)
  root              Install Magisk root
  restore           Remove root / relock the bootloader

Run a command with --help for its own options.
EOF
}

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then shift; fi

case "$cmd" in
  status)  exec "$DIR/scripts/status.sh" "$@" ;;
  backup)  exec "$DIR/scripts/backup.sh" "$@" ;;
  unlock)  exec "$DIR/scripts/unlock.sh" "$@" ;;
  root)    exec "$DIR/scripts/root.sh" "$@" ;;
  restore) exec "$DIR/scripts/restore.sh" "$@" ;;
  help|-h|--help) usage ;;
  *) usage; echo; echo "Unknown command: $cmd" >&2; exit 1 ;;
esac
