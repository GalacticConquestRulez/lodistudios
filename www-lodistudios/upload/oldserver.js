const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');

const app = express();

// Base URL of your public media player
const BASE_URL = 'http://159.223.127.113/mediaplayer';

// Set storage for multer
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
    cb(null, Date.now() + '-' + safeName);
  }
});

// Multer config with 50MB file limit
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

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

app.post('/upload', upload.fields([
  { name: 'song', maxCount: 1 },
  { name: 'art', maxCount: 1 }
]), (req, res) => {
  try {
    const songFile = req.files.song[0];
    const artFile = req.files.art[0];

    const {
      artist,
      album,
      artistDisplay,
      albumDisplay,
      songname
    } = req.body;

    const meta = {
      songname,
      artist,
      album,
      artistDisplay: artistDisplay || artist,
      albumDisplay: albumDisplay || album,
      songPath: `${BASE_URL}/songs/${encodeURIComponent(songFile.filename)}`,
      albumArtPath: `${BASE_URL}/albumart/${encodeURIComponent(artFile.filename)}`,
      uploadedAt: new Date().toISOString()
    };

    const metaSafeName = songname.replace(/[^a-z0-9]/gi, '_').toLowerCase();
    const metaFilename = `/var/www/lodistudios/mediaplayer/meta/${Date.now()}-${metaSafeName}.json`;

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
