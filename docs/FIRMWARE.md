# Firmware / OTA images

To root or unroot you need the **stock `init_boot.img` that matches the exact
build currently on the phone**. The toolkit fetches this for you and verifies it
by SHA-256. You normally don't have to do anything.

## Automatic (recommended)

`root.sh` and `restore.sh` call this automatically when you don't pass an image
explicitly. You can also run it yourself:

```bash
./np2a.sh firmware              # stock init_boot.img for the connected phone
./np2a.sh firmware --list       # show archived builds for your device
./np2a.sh firmware --partition boot
```

It works like this:

1. Reads `ro.product.device` (e.g. `Pacman`) and `ro.build.display.id`
   (e.g. `B4.1-260813-0941`) from the phone.
2. Finds the matching release in the community firmware archive,
   [`spike0en/nothing_archive`](https://github.com/spike0en/nothing_archive),
   tagged `<Codename>_<build>`.
3. Downloads that build's `-image-boot.7z` (~38 MB — it contains
   `boot`, `dtbo`, `init_boot`, `vendor_boot`, `vbmeta`).
4. Extracts `init_boot.img` and verifies its **SHA-256 against the archive's
   published `-hash.sha256` manifest**.
5. Caches the verified image under `.work/firmware/<tag>/` for instant reuse.

Nothing is redistributed by this toolkit; it downloads directly from the
archive's GitHub releases, which are built from images sourced from Nothing's
official OTA servers.

### When there's no matching release

If your phone updated to a build that hasn't been archived yet, `--list` shows
what exists. Options then:

- Downgrade/upgrade won't help for rooting — you must match the running build.
- Wait for the archive to add it, or
- Supply the firmware yourself with `--ota` / `--init-boot` (below).

## Manual: full OTA zip

If you have a **full OTA** (not incremental) for your build, pass it and the
toolkit extracts only `init_boot` with
[`payload-dumper-go`](https://github.com/ssut/payload-dumper-go) (auto-downloaded):

```bash
./np2a.sh root --ota ~/Downloads/Nothing_Phone_2a_full_ota.zip
./np2a.sh root --ota https://host.example/full-ota.zip     # several GB
```

`payload-dumper-go` reads the zip directly and verifies SHA-256 internally. To
inspect partitions in an OTA yourself:

```bash
.tools/payload-dumper-go -l <ota.zip>
```

## Manual: stock image

If you already have an extracted stock image:

```bash
./np2a.sh root --init-boot stock_init_boot.img     # patched on the phone by Magisk
./np2a.sh root --patched magisk_patched-XXXXX.img  # ready-patched image
```

## Build matching

The `init_boot` image must come from the **exact same build** as the phone
(`ro.build.display.id`). Flashing a mismatched image is the most common cause of
a bootloop. The automatic path guarantees a match; if you source an image
manually, verify the build string yourself.

Keep a copy of the extracted stock `init_boot.img` — you'll want it for
`restore.sh`.

## Dependencies

- `7z` (Arch: `7zip`, Debian: `p7zip-full`) to unpack the archive images.
- `xz` for `payload-dumper-go`.
- `curl` for downloads.

## Credit

Firmware images are the property of Nothing Technology Limited. OTA payload
extraction, archiving and hash manifests are provided by the independent
[Nothing Archive](https://github.com/spike0en/nothing_archive) project. This
toolkit only automates fetching from it; please respect that project's terms and
retain its notices if you redistribute images.
