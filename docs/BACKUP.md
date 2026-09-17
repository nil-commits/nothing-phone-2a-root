# Backing up before you unlock

Unlocking the bootloader factory-resets the phone, so back up **before** running
`./np2a.sh unlock`.

## What `backup.sh` copies

Everything an unrooted ADB connection can read, which is the shared storage
(`/sdcard`) plus `Android/media`:

```
DCIM  Pictures  Movies  Download  Documents  Music
Recordings  Podcasts  Audiobooks  Alarms  Notifications  Ringtones
Android/media
```

It also picks up loose `.vcf` / `.xml` / `.csv` exports sitting in the root of
`/sdcard` (handy for contact and SMS exports), writes `BACKUP-MANIFEST.txt`
(device model, build, serial, file count, size) and `SHA256SUMS.txt` so you can
verify the copy later:

```bash
cd ~/Nothing2a-Backup-YYYYMMDD-HHMMSS
sha256sum -c SHA256SUMS.txt
```

## What it does NOT copy

ADB cannot read app-private data (`/data/data/...`) or `/data/media` internals
without root. That means these are **not** in the backup unless the app itself
exports them:

- Chat history (WhatsApp, Signal, Telegram, ...)
- SMS/MMS and call logs
- Contacts (if not synced to your Google account)
- Saved passwords/2FA tokens (use an authenticator export or a password manager)
- App settings and saved game data

### Exporting app data first

Do these on the phone **before** `backup.sh`, saving into a folder it copies
(usually `Download`):

| Data | How |
| --- | --- |
| Contacts | Contacts app → Fix & manage → Export to file (`.vcf`) |
| SMS/MMS + call log | e.g. "SMS Backup & Restore" → back up to `Download` |
| WhatsApp | WhatsApp → Settings → Chats → Chat backup (and copy the `Databases` folder if rooted later) |
| Photos already in cloud | Google Photos / your gallery sync |
| Authenticators | Export from the app to a file, store it somewhere safe |
| Signal | Signal → Chats → Chat backups (writes a passphrase-protected file) |

## Larger backups

Media-heavy phones take longer. The script prints a per-folder progress line and
a final size. To back up somewhere else:

```bash
./np2a.sh backup --dest /run/media/you/ExternalDrive/np2a-backup
```

## After the backup

1. Confirm `SHA256SUMS.txt` verifies and open a few files.
2. Copy the backup folder to a second location (cloud or external disk).
3. Only then run `./np2a.sh unlock`.
