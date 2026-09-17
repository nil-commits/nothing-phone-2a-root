# Nothing Phone (2a) Rooting Toolkit

Scripts to **back up, unlock, root, and restore** the Nothing Phone (2a)
(`pacman` / `pacmanpro`) from Linux, macOS or WSL, using nothing but
`adb` + `fastboot` and [Magisk](https://github.com/topjohnwu/Magisk).

> **Unlocking the bootloader erases the phone.** Run `./np2a.sh backup` first.
> Nothing here is reversible without losing data, and root trips SafetyNet/Play
> Integrity, so banking and DRM apps may stop working. You are responsible for
> your own device.

## Why

Unlocking and rooting the Phone (2a) is a well-known but fiddly process: toggle
the right developer options, extract `init_boot.img` from a matching full OTA,
patch it in the Magisk app, and flash it to the correct A/B slot. This repo
packages that into a few small, auditable shell scripts and documents the sharp
edges (build matching, slot handling, relocking).

## Requirements

- The Nothing Phone (2a) with **USB debugging** enabled and the computer authorized.
- Linux/macOS with `adb` and `fastboot`:
  - Arch / CachyOS: `sudo pacman -S android-tools android-udev`
  - Debian / Ubuntu: `sudo apt install android-sdk-platform-tools-common`
  - macOS: `brew install android-platform-tools`
- `curl`, `xz` (used to download/extract firmware tooling).
- A **full OTA zip matching your exact build** (only needed for `root`/`restore`
  unless you already have an `init_boot.img`). See [docs/FIRMWARE.md](docs/FIRMWARE.md).

## Quick start

```bash
git clone <your-fork-url> nothing-phone-2a-root
cd nothing-phone-2a-root

./np2a.sh status                 # detect the phone and show lock/root state
./np2a.sh backup                 # 1. pull personal files (DO THIS FIRST)
./np2a.sh unlock                 # 2. unlock bootloader (factory reset)
./np2a.sh root --ota ~/Downloads/Nothing_Phone_2a_full_ota.zip   # 3. root with Magisk
./np2a.sh status                 # verify
```

Reload udev rules after installing `android-udev` so the phone is detected
without root:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## Commands

| Command | What it does |
| --- | --- |
| `./np2a.sh status` | Show model, build, OEM-unlock state and lock/root status. |
| `./np2a.sh backup [--dest DIR]` | Pull `/sdcard` (media, documents, exports) into a timestamped folder. |
| `./np2a.sh unlock` | Unlock the bootloader. **Wipes the device.** |
| `./np2a.sh root --ota ZIP` | Extract `init_boot.img`, patch via Magisk, flash it. |
| `./np2a.sh restore --init-boot FILE [--relock]` | Remove root; optionally relock. |

Every command supports `-h/--help`.

## How it works

### Unlock

1. Verifies the device is a Phone (2a) and that Developer options → **OEM
   unlocking** is enabled (`sys.oem_unlock_allowed`).
2. Reboots to the bootloader and runs `fastboot flashing unlock`.
3. You confirm on-screen (Volume keys + Power); the phone factory-resets.

Upstream reference: `fastboot flashing unlock` is the standard AOSP flow used by
all Nothing/CMF phones.

### Root

1. Extracts `init_boot.img` from your full OTA with
   [`payload-dumper-go`](https://github.com/ssut/payload-dumper-go) (auto-downloaded).
2. Pushes it to the phone and has the **Magisk app** patch it (Magisk patches on
   the device, not on the PC).
3. Pulls the resulting `magisk_patched-*.img`.
4. Flashes it to the active A/B slot (`init_boot_a`/`init_boot_b`, falling back
   to `init_boot`) and reboots.

> **Build matching matters.** The `init_boot` image must come from the exact
> same build as what is on the phone (`ro.build.display.id`). A mismatch can
> bootloop the device. When in doubt, re-extract from the OTA for your current
> build.

## Getting the firmware

You need a **full OTA** (not an incremental/delta OTA) for your exact build.
`root.sh --ota` accepts a local path or an `https://` URL and extracts only
`init_boot`, so you never need the whole 2–4 GB payload unpacked. Details and
options are in [docs/FIRMWARE.md](docs/FIRMWARE.md).

Alternatively, pass an already-extracted stock image with `--init-boot`, or a
pre-patched image with `--patched`.

## Restore / unroot

```bash
# Unroot, keep the bootloader unlocked:
./np2a.sh restore --ota ~/Downloads/Nothing_Phone_2a_full_ota.zip

# Unroot and relock (erases data again, requires fully stock):
./np2a.sh restore --init-boot stock_init_boot.img --relock
```

Relocking a modified device can make it refuse to boot. Only relock when
everything (both slots) is stock, and keep **OEM unlocking** enabled until you
are sure it boots.

## Alternatives to Magisk

This toolkit uses Magisk. If you prefer
[KernelSU](https://kernelsu.org/) or [APatch](https://github.com/bmax121/APatch),
the flash mechanics are the same: install their app, patch the stock
`init_boot.img`, then `fastboot flash init_boot_<slot>`. `root.sh --patched`
accepts any pre-patched image.

## Layout

```
np2a.sh              # entry point / dispatcher
scripts/
  common.sh          # shared helpers (device detection, fastboot, OTA extraction)
  backup.sh          # sdcard backup
  unlock.sh          # bootloader unlock
  root.sh            # Magisk root
  restore.sh         # unroot / relock
  status.sh          # device & lock/root status
docs/
  BACKUP.md          # what ADB can and cannot back up
  FIRMWARE.md        # obtaining and handling OTA images
```

## Safety notes

- `backup.sh` only reaches `/sdcard`. App-private data (chat history, saved game
  state, etc.) must be exported from inside each app. See [docs/BACKUP.md](docs/BACKUP.md).
- Keep `OEM unlocking` enabled while rooted; turning it off can soft-brick.
- This is unofficial and not affiliated with Nothing Technology Limited.

## License

MIT — see [LICENSE](LICENSE).
