# LodiStudios

AI music site and web media player, served by nginx from `/var/www/lodistudios`.

```
www-lodistudios/
  index.html              landing page
  mediaplayer/            the player
    player.html/.css/.js  the app itself
    serviceWorker.js      offline support / installable app
    meta/                 one .json per song, plus the generated index.json
    songs/  albumart/     media files
  upload/
    server.js             Node service that accepts new songs (localhost only)
    uploader.html         the upload form
deploy/
  nginx-lodistudios.conf  the nginx site config
  setup-security.sh       one-command installer
  lodistudios-uploader.service   runs the uploader on boot
```

## Deploying to the server

From a checkout on the server:

```bash
sudo ./deploy/setup-security.sh
```

It backs up everything it replaces to `/root/lodistudios-backup-<timestamp>/`,
asks you to set an uploader password, installs the nginx config and the
uploader service, and rebuilds the song list. Safe to run more than once.

## Adding a song

Go to `http://your-server/upload/` and sign in with the password you set.
The player picks up new songs automatically — `index.json` is rebuilt on
each upload.

To rebuild the song list by hand after editing metadata directly:

```bash
node /var/www/lodistudios/mediaplayer/meta/generateIndex.js
```

## Player keyboard shortcuts

| Key | Action |
|-----|--------|
| `Space` | play / pause |
| `←` `→` | seek 5s (hold `Alt` for previous / next track) |
| `↑` `↓` | volume |
| `M` | mute |
| `S` | shuffle |
| `R` | repeat (off → all → one) |
| `/` | jump to search |

## Notes

Song and artwork paths in `meta/*.json` are host-relative (`/mediaplayer/...`),
not absolute URLs. This is deliberate: it means the site works over http and
https, on the bare IP or on lodistudios.com, without editing any metadata.
Keep it that way when adding songs by hand.
