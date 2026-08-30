
const container = document.getElementById('songContainer');
let currentIndex = -1;
let songsList = [];
let globalAudio = new Audio();
let currentCard = null;

// Create a glowing button
function createButton(className, title, innerHTML) {
  const btn = document.createElement('button');
  btn.className = `btn-glow ${className}`;
  btn.title = title;
  btn.innerHTML = innerHTML;
  return btn;
}

function updateMediaSession(index) {
  if ('mediaSession' in navigator && songsList[index]) {
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

    navigator.mediaSession.setActionHandler('play', () => globalAudio.play());
    navigator.mediaSession.setActionHandler('pause', () => globalAudio.pause());
    navigator.mediaSession.setActionHandler('previoustrack', playPreviousSong);
    navigator.mediaSession.setActionHandler('nexttrack', playNextSong);
  }
}

function playSongAt(index) {
  if (index < 0 || index >= songsList.length) return;

  currentIndex = index;
  const song = songsList[index];

  globalAudio.src = song.songPath;
  globalAudio.play();

  if (currentCard) {
    currentCard.classList.remove('playing');
    const oldBtn = currentCard.querySelector('.btn-play');
    oldBtn.innerHTML = playIconSVG;
  }

  const card = container.children[index];
  const btn = card.querySelector('.btn-play');
  btn.innerHTML = pauseIconSVG;
  card.classList.add('playing');

  currentCard = card;

  updateMediaSession(index);
}

function playPreviousSong() {
  playSongAt(currentIndex > 0 ? currentIndex - 1 : songsList.length - 1);
}

function playNextSong() {
  playSongAt((currentIndex + 1) % songsList.length);
}

// SVG Icons
const playIconSVG = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" fill="none" viewBox="0 0 24 24" stroke="#FF4FA0" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 5l14 7-14 7"/></svg>`;
const pauseIconSVG = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" fill="none" viewBox="0 0 24 24" stroke="#FF4FA0" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>`;

function createSongCard(song, index) {
  const card = document.createElement('div');
  card.className = 'song-card';

  const albumArt = document.createElement('img');
  albumArt.src = song.albumArtPath;
  albumArt.alt = `Album art for ${song.albumDisplay || song.album || 'Unknown Album'}`;
  albumArt.className = 'album-art';

  const title = document.createElement('div');
  title.className = 'song-title';
  title.textContent = song.songname || 'Unknown Title';

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
        globalAudio.currentTime = 0;
        clickTimeout = null;
      }, 300);
    }
  };

  const btnPlay = createButton('btn-play', 'Play/Pause', playIconSVG);
  btnPlay.onclick = () => {
    if (!globalAudio.paused && currentIndex === index) {
      globalAudio.pause();
      btnPlay.innerHTML = playIconSVG;
      card.classList.remove('playing');
    } else {
      playSongAt(index);
    }
  };

  const btnNext = createButton('btn-next', 'Next', '>>');
  btnNext.onclick = () => playNextSong();

  const progressContainer = document.createElement('div');
  progressContainer.className = 'progress-container';
  const progressBar = document.createElement('div');
  progressBar.className = 'progress-bar';
  progressContainer.appendChild(progressBar);

  controls.appendChild(btnBack);
  controls.appendChild(btnPlay);
  controls.appendChild(btnNext);
  controls.appendChild(progressContainer);

  card.appendChild(albumArt);
  card.appendChild(title);
  card.appendChild(artist);
  card.appendChild(album);
  card.appendChild(controls);

  globalAudio.ontimeupdate = () => {
    if (globalAudio.duration) {
      const percent = (globalAudio.currentTime / globalAudio.duration) * 100;
      progressBar.style.width = percent + '%';
    }
  };

  progressContainer.onclick = (e) => {
    const rect = progressContainer.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const seekTime = (clickX / rect.width) * globalAudio.duration;
    globalAudio.currentTime = seekTime;
  };

  globalAudio.onended = () => {
    btnPlay.innerHTML = playIconSVG;
    card.classList.remove('playing');
    playNextSong();
  };

  return card;
}

fetch('/meta/index.json')
  .then(res => res.json())
  .then(data => {
    if (!Array.isArray(data)) throw new Error('Invalid song list');
    songsList = data;
    container.innerHTML = '';
    songsList.forEach((song, index) => {
      const card = createSongCard(song, index);
      container.appendChild(card);
    });
  })
  .catch(err => {
    container.innerHTML = `<p style="color:#ff4fa0; text-align:center; margin-top:40px;">Error loading songs: ${err.message}</p>`;
  });
