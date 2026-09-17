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
the right developer options, find the *exact* stock `init_boot.img` for your
build, extract it from a multi-GB OTA, patch it in the Magisk app, and flash it
to the correct A/B slot. This repo packages that into a few small, auditable
shell scripts.

The part most guides leave as homework — **sourcing and trusting the right stock
image** — is automated: the toolkit looks up your exact build in the
[community firmware archive](https://github.com/spike0en/nothing_archive),
downloads the small boot-image bundle, and verifies it by SHA-256 before use.

## Requirements

- The Nothing Phone (2a) with **USB debugging** enabled and the computer authorized.
- Linux/macOS with `adb`, `fastboot`, `curl`, `7z` and `xz`:
  - Arch / CachyOS: `sudo pacman -S android-tools android-udev curl 7zip xz`
  - Debian / Ubuntu: `sudo apt install android-sdk-platform-tools-common curl p7zip-full xz-utils`
  - macOS: `brew install android-platform-tools sevenzip xz`

No OTA download is required — the matching stock image is fetched automatically.
See [docs/FIRMWARE.md](docs/FIRMWARE.md) for the manual paths.

## Quick start

```bash
git clone https://github.com/nil-commits/nothing-phone-2a-root
cd nothing-phone-2a-root

./np2a.sh status     # detect the phone and show lock/root state
./np2a.sh backup     # 1. pull personal files (DO THIS FIRST)
./np2a.sh unlock     # 2. unlock bootloader (factory reset)
./np2a.sh root       # 3. fetch matching stock image, patch with Magisk, flash
./np2a.sh status     # verify
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
| `./np2a.sh root` | Fetch the matching stock `init_boot.img`, patch via Magisk, flash it. |
| `./np2a.sh restore [--relock]` | Remove root (fetching stock image if needed); optionally relock. |
| `./np2a.sh firmware [--list]` | Fetch and SHA-256-verify the stock image for your build. |

Overrides: `root`/`restore` also accept `--ota ZIP_OR_URL`, `--init-boot FILE`
and `--patched FILE`. Every command supports `-h/--help`.

## How it works

### Unlock

1. Verifies the device is a Phone (2a) and that Developer options → **OEM
   unlocking** is enabled (`sys.oem_unlock_allowed`).
2. Reboots to the bootloader and runs `fastboot flashing unlock`.
3. You confirm on-screen (Volume keys + Power); the phone factory-resets.

Upstream reference: `fastboot flashing unlock` is the standard AOSP flow used by
all Nothing/CMF phones.

### Root

1. Resolves the stock `init_boot.img` for your exact build:
   - automatic: matching release `<Codename>_<build>` in
     [`spike0en/nothing_archive`](https://github.com/spike0en/nothing_archive),
     SHA-256 verified (`-image-boot.7z`, ~38 MB); or
   - `--ota`: extracted with
     [`payload-dumper-go`](https://github.com/ssut/payload-dumper-go); or
   - `--init-boot` / `--patched` supplied by you.
2. Pushes the stock image to the phone and has the **Magisk app** patch it
   (Magisk patches on the device, not on the PC).
3. Pulls the resulting `magisk_patched-*.img`.
4. Flashes it to the active A/B slot (`init_boot_a`/`init_boot_b`, falling back
   to `init_boot`) and reboots.

> **Build matching matters.** The `init_boot` image must come from the exact
> same build as what is on the phone (`ro.build.display.id`). A mismatch can
> bootloop the device. The automatic path guarantees a match.

## Getting the firmware

Handled for you. `./np2a.sh firmware --list` shows archived builds for your
device; `./np2a.sh root` fetches and verifies the right one automatically.
Full details, manual options and credit are in
[docs/FIRMWARE.md](docs/FIRMWARE.md).

## Restore / unroot

```bash
# Unroot (fetches the matching stock image), keep bootloader unlocked:
./np2a.sh restore

# Unroot from a known stock image and relock (erases data again):
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
  common.sh          # shared helpers (device detection, fastboot, archive fetch)
  backup.sh          # sdcard backup
  unlock.sh          # bootloader unlock
  root.sh            # Magisk root
  restore.sh         # unroot / relock
  firmware.sh        # fetch + verify stock images from the archive
  status.sh          # device & lock/root status
docs/
  BACKUP.md          # what ADB can and cannot back up
  FIRMWARE.md        # firmware sourcing (automatic + manual)
```

## Safety notes

- `backup.sh` only reaches `/sdcard`. App-private data (chat history, saved game
  state, etc.) must be exported from inside each app. See [docs/BACKUP.md](docs/BACKUP.md).
- Keep `OEM unlocking` enabled while rooted; turning it off can soft-brick.
- Stock images are fetched from a third-party community archive; verify the
  printed SHA-256 check passes (it is enforced automatically).

## Credit

- Firmware archive, partition images and hash manifests:
  [spike0en/nothing_archive](https://github.com/spike0en/nothing_archive).
- OTA payload extraction: [`payload-dumper-go`](https://github.com/ssut/payload-dumper-go).
- Root: [Magisk](https://github.com/topjohnwu/Magisk).
- Firmware itself is the property of Nothing Technology Limited.

This project is unofficial and not affiliated with Nothing Technology Limited.

## License

MIT — see [LICENSE](LICENSE).

