/* LodiStudios upload service.
 *
 * SECURITY NOTES
 *  - Listens on 127.0.0.1 only. It is not reachable from the internet
 *    directly; nginx proxies to it and enforces HTTP Basic auth first.
 *  - `existingArt` is reduced to a bare filename before use. Previously a
 *    value like "../../../etc/passwd" reached fs.existsSync() and could be
 *    used to probe the filesystem.
 *  - Uploads no longer silently overwrite existing songs or artwork.
 *  - index.json is rebuilt after each upload, so new songs appear in the
 *    player without a manual step.
 */

const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const { build: rebuildIndex } = require('/var/www/lodistudios/mediaplayer/meta/generateIndex.js');

const app = express();
app.disable('x-powered-by');

const ROOT = '/var/www/lodistudios/mediaplayer';
const SONG_DIR = path.join(ROOT, 'songs');
const ART_DIR = path.join(ROOT, 'albumart');
const META_DIR = path.join(ROOT, 'meta');
const TMP_DIR = '/var/www/lodistudios/upload/tmp';

const HOST = process.env.UPLOAD_HOST || '127.0.0.1';
const PORT = Number(process.env.UPLOAD_PORT) || 3000;

for (const dir of [SONG_DIR, ART_DIR, META_DIR, TMP_DIR]) {
  fs.mkdirSync(dir, { recursive: true });
}

/* ---------- helpers ---------- */

const sanitize = (name) =>
  path.basename(String(name)).replace(/[^a-zA-Z0-9.\-_]/g, '_').slice(0, 120);

const slug = (name) =>
  String(name).replace(/[^a-z0-9]/gi, '_').toLowerCase().replace(/_+/g, '_')
    .replace(/^_|_$/g, '').slice(0, 80);

/** Return a path in `dir` that does not already exist, adding -1, -2, ... */
function uniquePath(dir, filename) {
  const ext = path.extname(filename);
  const base = path.basename(filename, ext);
  let candidate = path.join(dir, filename);
  let n = 1;
  while (fs.existsSync(candidate)) {
    candidate = path.join(dir, `${base}-${n}${ext}`);
    n++;
  }
  return candidate;
}

/* ---------- upload handling ---------- */

const storage = multer.diskStorage({
  // Everything lands in a temp dir first; nothing touches the live media
  // directories until the request has fully validated.
  destination: (req, file, cb) => cb(null, TMP_DIR),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${sanitize(file.originalname)}`),
});

// Browsers are inconsistent about the Content-Type they attach to an MP3 —
// plenty send application/octet-stream — so the extension is a soft check and
// the real gate is the magic-byte test below, which reads the actual file.
const ALLOWED = {
  song: { ext: ['.mp3'], mime: ['audio/mpeg', 'audio/mp3', 'audio/mpeg3', 'audio/x-mpeg-3', 'application/octet-stream', ''] },
  art: { ext: ['.jpg', '.jpeg', '.png'], mime: ['image/jpeg', 'image/png', 'application/octet-stream', ''] },
};

const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024, files: 2, fields: 20 },
  fileFilter: (req, file, cb) => {
    const rule = ALLOWED[file.fieldname];
    if (!rule) return cb(new Error(`Unexpected field "${file.fieldname}"`));
    const ext = path.extname(file.originalname).toLowerCase();
    if (!rule.ext.includes(ext)) return cb(new Error(`${file.fieldname}: expected ${rule.ext.join(' or ')}`));
    if (file.mimetype && !rule.mime.includes(file.mimetype)) {
      return cb(new Error(`${file.fieldname}: unexpected content type ${file.mimetype}`));
    }
    // Content itself is verified after the upload completes.
    cb(null, true);
  },
});

/** MP3s start with an ID3 tag or an MPEG frame sync. Catches a renamed file. */
function looksLikeMp3(filePath) {
  const fd = fs.openSync(filePath, 'r');
  const buf = Buffer.alloc(3);
  try { fs.readSync(fd, buf, 0, 3, 0); } finally { fs.closeSync(fd); }
  return buf.toString('latin1', 0, 3) === 'ID3' || (buf[0] === 0xff && (buf[1] & 0xe0) === 0xe0);
}

function cleanup(files) {
  for (const list of Object.values(files || {})) {
    for (const f of list) fs.promises.unlink(f.path).catch(() => {});
  }
}

app.use(express.urlencoded({ extended: true, limit: '1mb' }));

app.post('/upload', (req, res) => {
  upload.fields([{ name: 'song', maxCount: 1 }, { name: 'art', maxCount: 1 }])(req, res, async (uploadErr) => {
    if (uploadErr) {
      cleanup(req.files);
      return res.status(400).send(`Upload rejected: ${uploadErr.message}`);
    }

    const files = req.files || {};
    try {
      const songFile = files.song && files.song[0];
      if (!songFile) return res.status(400).send('No MP3 was supplied.');

      const { existingArt, artist, album, artistDisplay, albumDisplay, songname } = req.body;

      if (!songname || !String(songname).trim()) return res.status(400).send('Song title is required.');
      if (!artist || !String(artist).trim()) return res.status(400).send('Artist is required.');

      const baseName = slug(songname);
      if (!baseName) return res.status(400).send('Song title must contain letters or numbers.');

      if (!looksLikeMp3(songFile.path)) return res.status(400).send('That file is not a valid MP3.');

      /* --- album art ------------------------------------------------- */
      let albumArtFilename = null;

      if (existingArt) {
        // path.basename() strips any ../ segments before the path is built.
        const safeExisting = path.basename(String(existingArt));
        const existingPath = path.join(ART_DIR, safeExisting);
        if (path.dirname(existingPath) !== ART_DIR || !fs.existsSync(existingPath)) {
          return res.status(400).send('Selected album art does not exist.');
        }
        albumArtFilename = safeExisting;
      } else if (files.art && files.art[0]) {
        const target = uniquePath(ART_DIR, `${baseName}_AlbumArt.jpg`);
        try {
          await sharp(files.art[0].path)
            .resize(512, 512, { fit: 'cover', position: 'centre' })
            .jpeg({ quality: 90 })
            .toFile(target);
        } catch {
          return res.status(400).send('That album art is not a readable image.');
        }
        albumArtFilename = path.basename(target);
      }

      /* --- move the song into place ---------------------------------- */
      const songTarget = uniquePath(SONG_DIR, sanitize(songFile.originalname));
      await fs.promises.rename(songFile.path, songTarget).catch(async (err) => {
        if (err.code !== 'EXDEV') throw err;      // different filesystem
        await fs.promises.copyFile(songFile.path, songTarget);
        await fs.promises.unlink(songFile.path);
      });
      const songFilename = path.basename(songTarget);

      /* --- metadata --------------------------------------------------- */
      const meta = {
        songname: String(songname).trim(),
        artist: String(artist).trim(),
        album: String(album || '').trim(),
        artistDisplay: String(artistDisplay || artist).trim(),
        albumDisplay: String(albumDisplay || album || '').trim(),
        songPath: `/mediaplayer/songs/${encodeURIComponent(songFilename)}`,
        albumArtPath: albumArtFilename ? `/mediaplayer/albumart/${encodeURIComponent(albumArtFilename)}` : null,
        uploadedAt: new Date().toISOString(),
      };

      const metaPath = uniquePath(META_DIR, `${baseName}.json`);
      await fs.promises.writeFile(metaPath, JSON.stringify(meta, null, 2) + '\n');

      const { count } = rebuildIndex();

      res.send(`Uploaded "${meta.songname}". The player now lists ${count} songs.`);
    } catch (err) {
      console.error('Upload error:', err);
      res.status(500).send(`Upload failed: ${err.message}`);
    } finally {
      // Runs on every exit path, including the early 400s above. Files that
      // were successfully renamed into place are already gone; unlink just
      // no-ops on them.
      cleanup(files);
    }
  });
});

// nginx serves the form; this only fires if something reaches Node directly.
app.get('/upload', (req, res) => res.redirect('/upload/'));

app.get('/healthz', (req, res) => res.send('ok'));

app.listen(PORT, HOST, () => console.log(`Uploader listening on http://${HOST}:${PORT}`));
