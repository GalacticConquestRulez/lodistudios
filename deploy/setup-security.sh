#!/usr/bin/env bash
#
# Applies the LodiStudios security fixes to this server.
# Run as root, from the repo checkout:
#
#     sudo ./deploy/setup-security.sh
#
# It is safe to run more than once. Everything it replaces is backed up
# to /root/lodistudios-backup-<timestamp>/ first.
#
set -euo pipefail

WEB_ROOT=/var/www/lodistudios
HTPASSWD=/etc/nginx/.htpasswd-lodistudios
SITE_AVAILABLE=/etc/nginx/sites-available/lodistudios
SITE_ENABLED=/etc/nginx/sites-enabled/lodistudios
BACKUP="/root/lodistudios-backup-$(date +%Y%m%d-%H%M%S)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[0;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[0;33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[0;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run this with sudo:  sudo $0"
[ -d "$WEB_ROOT" ] || die "$WEB_ROOT not found. Is this the right server?"

mkdir -p "$BACKUP"
say "Backing up to $BACKUP"
[ -f "$SITE_AVAILABLE" ] && cp "$SITE_AVAILABLE" "$BACKUP/nginx-lodistudios.conf.old" && ok "saved old nginx config"
cp -r "$WEB_ROOT/mediaplayer/meta" "$BACKUP/meta" 2>/dev/null && ok "saved song metadata"

# --- 1. password for the uploader ------------------------------------------
say "Uploader password"
if [ -f "$HTPASSWD" ]; then
    ok "password file already exists ($HTPASSWD)"
    warn "to add or change a user:  sudo htpasswd $HTPASSWD <username>"
else
    if ! command -v htpasswd >/dev/null; then
        say "Installing apache2-utils (provides htpasswd)"
        apt-get update -qq && apt-get install -y -qq apache2-utils
    fi
    read -rp "    Choose a username for the uploader: " UPLOAD_USER
    [ -n "$UPLOAD_USER" ] || die "Username cannot be empty."
    htpasswd -c "$HTPASSWD" "$UPLOAD_USER"
    chown root:www-data "$HTPASSWD"
    chmod 640 "$HTPASSWD"
    ok "password set for '$UPLOAD_USER'"
fi

# --- 2. remove publicly downloadable archives -------------------------------
say "Removing archives from the web root"
shopt -s nullglob
ARCHIVES=("$WEB_ROOT"/*.zip "$WEB_ROOT"/*.tar.gz "$WEB_ROOT"/*.sql)
if [ ${#ARCHIVES[@]} -gt 0 ]; then
    for f in "${ARCHIVES[@]}"; do
        mv "$f" "$BACKUP/"
        ok "moved $(basename "$f") out of the web root (kept in the backup)"
    done
else
    ok "none found"
fi
shopt -u nullglob

# --- 3. nginx ---------------------------------------------------------------
say "Installing nginx config"
cp "$HERE/nginx-lodistudios.conf" "$SITE_AVAILABLE"
ln -sfn "$SITE_AVAILABLE" "$SITE_ENABLED"
if [ -e /etc/nginx/sites-enabled/ai-music ]; then
    rm -f /etc/nginx/sites-enabled/ai-music
    ok "disabled the old ai-music site (it shadowed the main config)"
fi
nginx -t || die "nginx rejected the config. Your old config is in $BACKUP and is still live until you reload."
systemctl reload nginx
ok "nginx reloaded"

# --- 4. uploader service ----------------------------------------------------
say "Upload service"
if [ -d "$WEB_ROOT/upload" ]; then
    if command -v npm >/dev/null; then
        (cd "$WEB_ROOT/upload" && npm install --omit=dev --silent) && ok "dependencies installed"
    else
        warn "npm not found — install Node.js, then run: cd $WEB_ROOT/upload && npm install"
    fi

    install -m 644 "$HERE/lodistudios-uploader.service" /etc/systemd/system/lodistudios-uploader.service
    systemctl daemon-reload
    systemctl enable --now lodistudios-uploader >/dev/null 2>&1 || true
    systemctl restart lodistudios-uploader

    sleep 1
    if systemctl is-active --quiet lodistudios-uploader; then
        ok "uploader running on 127.0.0.1:3000 (not reachable from the internet)"
    else
        warn "uploader did not start. Check:  journalctl -u lodistudios-uploader -n 40"
    fi
fi

# --- 5. rebuild the catalogue ----------------------------------------------
say "Rebuilding the song list"
if command -v node >/dev/null; then
    node "$WEB_ROOT/mediaplayer/meta/generateIndex.js"
else
    warn "node not found — skipped. index.json is already up to date in the repo."
fi

# --- 6. permissions ---------------------------------------------------------
say "Fixing file permissions"
chown -R www-data:www-data "$WEB_ROOT/mediaplayer"
find "$WEB_ROOT/mediaplayer" -type d -exec chmod 755 {} +
find "$WEB_ROOT/mediaplayer" -type f -exec chmod 644 {} +
ok "media files owned by www-data"

say "Done"
cat <<SUMMARY

  Player     http://159.223.127.113/mediaplayer/
  Uploader   http://159.223.127.113/upload/   (asks for your password now)

  Backup of everything replaced: $BACKUP

  Next step worth taking: put the site on HTTPS. Once lodistudios.com
  points here, run:

      sudo apt install certbot python3-certbot-nginx
      sudo certbot --nginx -d lodistudios.com -d www.lodistudios.com

SUMMARY
