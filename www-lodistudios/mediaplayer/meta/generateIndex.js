#!/usr/bin/env node
/* Rebuilds index.json from the individual song metadata files.
   Run after adding or editing anything in this directory:
       node /var/www/lodistudios/mediaplayer/meta/generateIndex.js
   The uploader calls this automatically after each successful upload. */

const fs = require('fs');
const path = require('path');

const META_DIR = __dirname;
const INDEX_PATH = path.join(META_DIR, 'index.json');
const REQUIRED = ['songname', 'songPath'];

function build() {
  const files = fs.readdirSync(META_DIR)
    .filter((f) => f.endsWith('.json') && f !== 'index.json');

  const songs = [];
  const skipped = [];

  for (const filename of files) {
    try {
      const song = JSON.parse(fs.readFileSync(path.join(META_DIR, filename), 'utf8'));
      const missing = REQUIRED.filter((k) => !song[k]);
      if (missing.length) {
        skipped.push(`${filename} (missing ${missing.join(', ')})`);
        continue;
      }
      // Keep paths host-relative so the player works over http, https and any domain.
      for (const key of ['songPath', 'albumArtPath']) {
        if (typeof song[key] === 'string') song[key] = song[key].replace(/^https?:\/\/[^/]+/, '');
      }
      songs.push(song);
    } catch (err) {
      skipped.push(`${filename} (${err.message})`);
    }
  }

  songs.sort((a, b) =>
    String(a.artistDisplay || a.artist || '').localeCompare(String(b.artistDisplay || b.artist || '')) ||
    String(a.songname).localeCompare(String(b.songname))
  );

  // Write to a temp file then rename, so a reader never sees a half-written index.
  const tmp = `${INDEX_PATH}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(songs, null, 2) + '\n');
  fs.renameSync(tmp, INDEX_PATH);

  return { count: songs.length, skipped };
}

if (require.main === module) {
  try {
    const { count, skipped } = build();
    console.log(`index.json rebuilt with ${count} song(s).`);
    skipped.forEach((s) => console.warn(`  skipped: ${s}`));
  } catch (err) {
    console.error('Failed to rebuild index.json:', err.message);
    process.exit(1);
  }
}

module.exports = { build };
