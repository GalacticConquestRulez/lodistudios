const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const app = express();

const BASE_URL = 'http://159.223.127.113/mediaplayer';

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    if (file.fieldname === 'song') {
      cb(null, '/var/www/lodistudios/mediaplayer/songs');
    } else if (file.fieldname === 'art') {
      cb(null, '/var/www/lodistudios/mediaplayer/albumart');
    } else {
      cb(new Error('Unknown file field'));
    }
  },
  filename: (req, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9.\-_]/g, '_');
    cb(null, safeName);
  }
});

const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (file.fieldname === 'song' && ext === '.mp3') {
      cb(null, true);
    } else if (file.fieldname === 'art' && ['.jpg', '.jpeg', '.png'].includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type'));
    }
  }
});

async function processAlbumArt(inputPath, outputDir, baseName) {
  const outputFilename = `${baseName}_AlbumArt.jpg`;
  const outputPath = path.join(outputDir, outputFilename);

  if (fs.existsSync(outputPath)) {
    console.log(`Overwriting existing album art: ${outputFilename}`);
  }

  await sharp(inputPath)
    .resize(512, 512, {
      fit: 'cover',
      position: 'centre'
    })
    .jpeg({ quality: 90 })
    .toFile(outputPath);

  return outputFilename;
}

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

app.post('/upload', upload.fields([
  { name: 'song', maxCount: 1 },
  { name: 'art', maxCount: 1 }
]), async (req, res) => {
  try {
    const songFile = req.files.song[0];
    const { existingArt, artist, album, artistDisplay, albumDisplay, songname } = req.body;

    const baseName = songname.replace(/[^a-z0-9]/gi, '_').toLowerCase();
    const albumArtDir = '/var/www/lodistudios/mediaplayer/albumart';
    const metaDir = '/var/www/lodistudios/mediaplayer/meta';

    let albumArtFilename;

    if (existingArt) {
      const existingArtPath = path.join(albumArtDir, existingArt);
      if (!fs.existsSync(existingArtPath)) {
        return res.status(400).send('Selected existing album art file does not exist.');
      }
      albumArtFilename = existingArt;
    } else if (req.files.art && req.files.art.length > 0) {
      const artFile = req.files.art[0];
      albumArtFilename = await processAlbumArt(artFile.path, albumArtDir, baseName);
      fs.unlink(artFile.path, (err) => {
        if (err) console.warn('Failed to delete original art upload:', err);
      });
    } else {
      albumArtFilename = null;
    }

    const meta = {
      songname,
      artist,
      album,
      artistDisplay: artistDisplay || artist,
      albumDisplay: albumDisplay || album,
      songPath: `${BASE_URL}/songs/${encodeURIComponent(songFile.filename)}`,
      albumArtPath: albumArtFilename ? `${BASE_URL}/albumart/${encodeURIComponent(albumArtFilename)}` : null,
      uploadedAt: new Date().toISOString()
    };

    const metaFilename = path.join(metaDir, `${baseName}.json`);
    fs.writeFile(metaFilename, JSON.stringify(meta, null, 2), (err) => {
      if (err) {
        console.error('Metadata write error:', err);
        return res.status(500).send('Failed to write metadata');
      }
      res.send('Upload and metadata saved!');
    });
  } catch (err) {
    console.error('Upload error:', err);
    res.status(500).send('Upload failed: ' + err.message);
  }
});

const PORT = 3000;
app.listen(PORT, () => console.log(`Uploader ready on port ${PORT}`));
