const container = document.getElementById('songContainer');
let currentAudio = null;
let currentCard = null;
let currentIndex = -1;
let songsList = [];

// Button creation helper
function createButton(className, title, innerHTML) {
  const btn = document.createElement('button');
  btn.className = `btn-glow ${className}`;
  btn.title = title;
  btn.innerHTML = innerHTML;
  return btn;
}

// Icon toggle helpers
function setPlayIcon(btn) {
  btn.innerHTML = '▶';
  btn.classList.remove('pause-icon');
}
function setPauseIcon(btn) {
  btn.innerHTML = '';
  btn.classList.add('pause-icon');
}

// Play a song by index
function playSongAt(index) {
  if (index < 0 || index >= songsList.length) return;

  if (currentAudio) {
    currentAudio.pause();
    if (currentCard) {
      currentCard.classList.remove('playing');
      const btnPlay = currentCard.querySelector('.btn-play');
      setPlayIcon(btnPlay);
    }
  }

  currentIndex = index;
  const card = container.children[index];
  const audio = card.querySelector('audio');
  const btnPlay = card.querySelector('.btn-play');

  audio.currentTime = 0;
  audio.play();

  // Update media metadata for lock screen / external devices
  if ('mediaSession' in navigator) {
    const song = songsList[index];
    navigator.mediaSession.metadata = new MediaMetadata({
      title: song.songname || 'Unknown Title',
      artist: song.artist || 'Unknown Artist',
      album: song.album || 'Unknown Album',
      artwork: [
        { src: song.albumArtPath, sizes: '512x512', type: 'image/jpeg' },
        { src: song.albumArtPath, sizes: '256x256', type: 'image/jpeg' }
      ]
    });
  }

  setPauseIcon(btnPlay);
  card.classList.add('playing');

  currentAudio = audio;
  currentCard = card;
}

function playPreviousSong() {
  if (currentIndex <= 0) {
    playSongAt(songsList.length - 1);
  } else {
    playSongAt(currentIndex - 1);
  }
}

function playNextSong() {
  if (currentIndex >= songsList.length - 1) {
    playSongAt(0);
  } else {
    playSongAt(currentIndex + 1);
  }
}

function createSongCard(song, index) {
  const card = document.createElement('div');
  card.className = 'song-card';

  const audio = document.createElement('audio');
  audio.src = song.songPath;
  audio.preload = 'metadata';

  const albumArt = document.createElement('img');
  albumArt.src = song.albumArtPath;
  albumArt.alt = `Album art for ${song.albumDisplay || song.album || 'Unknown Album'}`;
  albumArt.className = 'album-art';

  const title = document.createElement('div');
  title.className = 'song-title';
  title.textContent = song.songname || 'Unknown Title';

  // Added artist and album display
  const artist = document.createElement('div');
  artist.className = 'song-artist';
  artist.textContent = song.artistDisplay || song.artist || 'Unknown Artist';

  const album = document.createElement('div');
  album.className = 'song-album';
  album.textContent = song.albumDisplay || song.album || 'Unknown Album';

  const controls = document.createElement('div');
  controls.className = 'card-controls';

  const btnBack = createButton('btn-back', 'Back (click: restart, dblclick: previous)', '<<');
  let clickTimeout = null;
  btnBack.onclick = () => {
    if (clickTimeout !== null) {
      clearTimeout(clickTimeout);
      clickTimeout = null;
      playPreviousSong();
    } else {
      clickTimeout = setTimeout(() => {
        if (!audio.paused) audio.currentTime = 0;
        clickTimeout = null;
      }, 300);
    }
  };

  const btnPlay = createButton('btn-play', 'Play/Pause', '▶');
  btnPlay.onclick = () => {
    if (!audio.paused) {
      audio.pause();
      setPlayIcon(btnPlay);
      card.classList.remove('playing');
      if (currentAudio === audio) {
        currentAudio = null;
        currentCard = null;
      }
    } else {
      if (currentAudio && currentAudio !== audio) {
        currentAudio.pause();
        if (currentCard) {
          currentCard.classList.remove('playing');
          setPlayIcon(currentCard.querySelector('.btn-play'));
        }
      }
      audio.play();
      setPauseIcon(btnPlay);
      card.classList.add('playing');
      currentAudio = audio;
      currentCard = card;
      currentIndex = index;
    }
  };

  const btnNext = createButton('btn-next', 'Next', '>>');
  btnNext.onclick = () => playNextSong();

  const btnAirPlay = createButton('btn-airplay', 'AirPlay', '⎘');
  btnAirPlay.onclick = () => alert('AirPlay feature not implemented yet');

  const progressContainer = document.createElement('div');
  progressContainer.className = 'progress-container';
  const progressBar = document.createElement('div');
  progressBar.className = 'progress-bar';
  progressContainer.appendChild(progressBar);

  controls.appendChild(btnBack);
  controls.appendChild(btnPlay);
  controls.appendChild(btnNext);
  controls.appendChild(btnAirPlay);
  controls.appendChild(progressContainer);

  card.appendChild(albumArt);
  card.appendChild(title);
  card.appendChild(artist);   // artist display
  card.appendChild(album);    // album display
  card.appendChild(controls);
  card.appendChild(audio);

  // Progress bar update
  audio.ontimeupdate = () => {
    if (audio.duration) {
      const percent = (audio.currentTime / audio.duration) * 100;
      progressBar.style.width = percent + '%';
    }
  };

  // Seek on progress bar click
  progressContainer.onclick = (e) => {
    const rect = progressContainer.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const width = rect.width;
    const seekTime = (clickX / width) * audio.duration;
    audio.currentTime = seekTime;
  };

  audio.onended = () => {
    setPlayIcon(btnPlay);
    card.classList.remove('playing');
    playNextSong();
  };

  return card;
}

// Fetch and load songs
fetch('/meta/index.json')
  .then(res => {
    if (!res.ok) throw new Error('Failed to fetch songs');
    return res.json();
  })
  .then(data => {
    if (!Array.isArray(data) || data.length === 0) {
      container.innerHTML = '<p style="color:#ff4fa0; text-align:center; margin-top:40px;">No songs available</p>';
      return;
    }
    songsList = data;
    container.innerHTML = '';
    data.forEach((song, idx) => {
      const card = createSongCard(song, idx);
      container.appendChild(card);
    });
  })
  .catch(err => {
    container.innerHTML = `<p style="color:#ff4fa0; text-align:center; margin-top:40px;">Error loading songs: ${err.message}</p>`;
  });
