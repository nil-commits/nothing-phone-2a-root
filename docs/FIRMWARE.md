# Firmware / OTA images

To root or unroot you need the **stock `init_boot.img` that matches the exact
build currently on the phone**. This document explains how to get it.

## 1. Find your build

```bash
adb shell getprop ro.build.display.id
adb shell getprop ro.build.version.release
```

Example: `B4.1-260813-0941` on Android 16. Write this down — the image you flash
must come from this same build. Flashing an `init_boot` from a different build
is the most common cause of a bootloop.

## 2. Get a FULL OTA zip for that build

`init_boot` lives inside the OTA's `payload.bin`. You need a **full** OTA, not an
incremental/delta one.

Ways to obtain it:

- **Let the phone fetch it, then grab the zip.** When the phone downloads an
  update, the package lands in `/data/ota_package/` (inaccessible via ADB
  without root) — a rooted friend's device or a prior capture is needed to copy it.
- **Community mirrors.** Nothing ships OTAs from its own servers; the community
  archives them and indexes them by build string. Search for your exact
  `ro.build.display.id` value plus `Nothing Phone 2a full OTA`. Prefer a source
  that publishes SHA-256 checksums and matches your region/variant.
- **Vendor/repair tools.** Some firmware aggregators host the full zips.

Because these sources change, this toolkit does not hardcode a download URL. Pass
the path (or an `https://` URL) you obtained:

```bash
./np2a.sh root --ota ~/Downloads/Nothing_Phone_2a_B4.1-260813-0941.zip
./np2a.sh root --ota https://host.example/path/full-ota.zip
```

If you only have an **incremental** OTA, `payload-dumper-go` can apply it on top
of a full OTA of the *previous* build using its `-old` flag, but it is simpler to
find the full OTA for your build.

## 3. What the toolkit extracts

`root.sh`/`restore.sh` call
[payload-dumper-go](https://github.com/ssut/payload-dumper-go) (auto-downloaded
to `.tools/`) and run, in effect:

```bash
payload-dumper-go -o .work/dumped -p init_boot -q <ota.zip>
```

The utility reads the OTA zip directly (no need to unzip `payload.bin`
yourself), verifies SHA-256 internally, and writes `init_boot.img` (~8 MB).

To inspect an OTA's partitions yourself:

```bash
.tools/payload-dumper-go -l <ota.zip>
```

## 4. If you already have `init_boot.img`

Skip the OTA entirely:

```bash
./np2a.sh root --init-boot stock_init_boot.img     # patched on the phone by Magisk
./np2a.sh root --patched magisk_patched-XXXXX.img  # ready-patched image
```

## 5. Verifying a build match

Two independent checks you can do after extracting:

```bash
# Extract vbmeta too and compare the security patch level, or simply confirm the
# OTA filename/folder is the build printed by:
adb shell getprop ro.build.display.id
```

Keep the extracted stock `init_boot.img` for your build in a safe place — you
will want it for `restore.sh`, and re-downloading a multi-GB OTA later is
annoying.

## Dependencies

`payload-dumper-go` needs `xz` at runtime. Install it if missing
(`sudo pacman -S xz`, `sudo apt install xz-utils`, `brew install xz`).
