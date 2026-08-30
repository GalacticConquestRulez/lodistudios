/* ==========================================================================
   LodiStudios media player

   Structure note: the <audio> element gets its event listeners exactly ONCE,
   at startup. Everything they touch is looked up through the current track,
   never captured from the row that happened to be built last. (The previous
   version assigned ontimeupdate/onended inside the per-song loop, so only
   the final card's handlers survived and the wrong progress bar animated.)
   ========================================================================== */

'use strict';

const INDEX_URL = '/mediaplayer/meta/index.json';
const STORE_KEY = 'lodistudios.player.v2';

/* ---------- element lookup ---------- */

const $ = (id) => document.getElementById(id);

const el = {
  ambient: $('ambient'),
  search: $('search'),
  filters: $('filters'),
  heroArt: $('heroArt'),
  heroEyebrow: $('heroEyebrow'),
  heroTitle: $('heroTitle'),
  heroMeta: $('heroMeta'),
  heroPlay: $('heroPlay'),
  heroPlayLabel: $('heroPlayLabel'),
  heroShuffle: $('heroShuffle'),
  tracklist: $('tracklist'),
  listCount: $('listCount'),
  listHeading: $('listHeading'),
  empty: $('empty'),
  playbar: $('playbar'),
  pbArt: $('pbArt'),
  pbTitle: $('pbTitle'),
  pbArtist: $('pbArtist'),
  btnPlay: $('btnPlay'),
  btnPrev: $('btnPrev'),
  btnNext: $('btnNext'),
  btnShuffle: $('btnShuffle'),
  btnRepeat: $('btnRepeat'),
  repeatOne: $('repeatOne'),
  btnMute: $('btnMute'),
  seek: $('seek'),
  seekFill: $('seekFill'),
  seekBuffer: $('seekBuffer'),
  timeNow: $('timeNow'),
  timeTotal: $('timeTotal'),
  vol: $('vol'),
  volFill: $('volFill'),
  toast: $('toast'),
};

/* ---------- state ---------- */

const audio = new Audio();
audio.preload = 'metadata';
// iOS (lock screen, CarPlay) registers the Now Playing session from an
// element that is in the document; a detached `new Audio()` frequently
// never shows up. It stays hidden — the UI is our own.
audio.setAttribute('playsinline', '');
audio.hidden = true;

const state = {
  all: [],        // every track from index.json
  queue: [],      // tracks currently listed (after search / artist filter)
  order: [],      // indices into queue, in playback order
  pos: -1,        // position within order
  shuffle: false,
  repeat: 'off',  // 'off' | 'all' | 'one'
  artist: 'All',
  search: '',
  seeking: false,
  durations: new Map(),
};

const prefs = loadPrefs();
state.shuffle = !!prefs.shuffle;
state.repeat = ['off', 'all', 'one'].includes(prefs.repeat) ? prefs.repeat : 'off';
audio.volume = typeof prefs.volume === 'number' ? clamp(prefs.volume, 0, 1) : 1;
audio.muted = !!prefs.muted;

function loadPrefs() {
  try { return JSON.parse(localStorage.getItem(STORE_KEY)) || {}; }
  catch { return {}; }
}
function savePrefs() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({
      volume: audio.volume, muted: audio.muted,
      shuffle: state.shuffle, repeat: state.repeat,
    }));
  } catch { /* private mode — preferences just won't persist */ }
}

/* ---------- helpers ---------- */

function clamp(n, lo, hi) { return Math.min(hi, Math.max(lo, n)); }

function fmtTime(secs) {
  if (!Number.isFinite(secs) || secs < 0) return '0:00';
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

let toastTimer;
function toast(msg) {
  el.toast.textContent = msg;
  el.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.toast.hidden = true; }, 3200);
}

const current = () => state.queue[state.order[state.pos]] || null;

/* ---------- rendering ---------- */

function render() {
  const term = state.search.trim().toLowerCase();

  state.queue = state.all.filter((s) => {
    if (state.artist !== 'All' && (s.artistDisplay || s.artist) !== state.artist) return false;
    if (!term) return true;
    return [s.songname, s.artistDisplay, s.artist, s.albumDisplay, s.album]
      .filter(Boolean)
      .some((v) => String(v).toLowerCase().includes(term));
  });

  el.tracklist.innerHTML = '';
  const frag = document.createDocumentFragment();

  state.queue.forEach((song, i) => {
    const li = document.createElement('li');
    li.className = 'track';
    li.tabIndex = 0;
    li.dataset.i = String(i);
    li.setAttribute('role', 'button');
    li.setAttribute('aria-label', `Play ${song.songname || 'track'} by ${song.artistDisplay || song.artist || 'unknown artist'}`);

    const idx = document.createElement('div');
    idx.className = 't-index';
    idx.innerHTML =
      `<span class="num">${i + 1}</span>` +
      `<svg class="cue" viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>` +
      `<span class="eq"><span></span><span></span><span></span></span>`;

    const art = document.createElement('img');
    art.className = 't-art';
    art.loading = 'lazy';
    art.alt = '';
    if (song.albumArtPath) art.src = song.albumArtPath;

    const main = document.createElement('div');
    main.className = 't-main';
    const title = document.createElement('span');
    title.className = 't-title';
    title.textContent = song.songname || 'Untitled';
    const artist = document.createElement('span');
    artist.className = 't-artist';
    artist.textContent = song.artistDisplay || song.artist || 'Unknown artist';
    main.append(title, artist);

    const album = document.createElement('div');
    album.className = 't-album';
    album.textContent = song.albumDisplay || song.album || '';

    const time = document.createElement('div');
    time.className = 't-time';
    time.textContent = state.durations.has(song.songPath)
      ? fmtTime(state.durations.get(song.songPath)) : '--:--';

    li.append(idx, art, main, album, time);
    frag.appendChild(li);
  });

  el.tracklist.appendChild(frag);
  el.empty.hidden = state.queue.length > 0;
  el.listCount.textContent = state.queue.length
    ? `${state.queue.length} track${state.queue.length === 1 ? '' : 's'}` : '';
  el.listHeading.textContent = state.artist === 'All' ? 'All tracks' : state.artist;

  rebuildOrder();
  markCurrent();
}

function renderFilters() {
  const artists = ['All', ...new Set(state.all.map((s) => s.artistDisplay || s.artist).filter(Boolean))];
  el.filters.innerHTML = '';
  artists.forEach((name) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.textContent = name;
    b.setAttribute('aria-pressed', String(name === state.artist));
    b.onclick = () => {
      state.artist = name;
      [...el.filters.children].forEach((c) => c.setAttribute('aria-pressed', String(c === b)));
      render();
    };
    el.filters.appendChild(b);
  });
}

/* Keep the playing track selected even as the visible list changes. */
function rebuildOrder() {
  const playing = audio.src ? decodeURI(audio.src) : null;
  state.order = state.queue.map((_, i) => i);

  if (state.shuffle) {
    for (let i = state.order.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [state.order[i], state.order[j]] = [state.order[j], state.order[i]];
    }
  }

  state.pos = -1;
  if (playing) {
    const qi = state.queue.findIndex((s) => decodeURI(new URL(s.songPath, location.href).href) === playing);
    if (qi !== -1) state.pos = state.order.indexOf(qi);
  }
}

function markCurrent() {
  const song = current();
  [...el.tracklist.children].forEach((row) => {
    const isCur = song && Number(row.dataset.i) === state.order[state.pos];
    row.classList.toggle('current', !!isCur);
    row.classList.toggle('playing', !!isCur && !audio.paused);
  });
}

/* ---------- now playing ---------- */

function paintHero(song) {
  el.heroEyebrow.textContent = audio.paused ? 'Paused' : 'Now playing';
  el.heroTitle.textContent = song.songname || 'Untitled';
  el.heroMeta.textContent = [song.artistDisplay || song.artist, song.albumDisplay || song.album]
    .filter(Boolean).join(' · ');
  el.heroPlayLabel.textContent = audio.paused ? 'Play' : 'Pause';

  if (song.albumArtPath) {
    el.heroArt.src = song.albumArtPath;
    el.pbArt.src = song.albumArtPath;
    el.heroArt.alt = `Album art for ${song.albumDisplay || song.album || 'this track'}`;
    setAmbient(song.albumArtPath);
  }
  el.pbTitle.textContent = song.songname || 'Untitled';
  el.pbArtist.textContent = song.artistDisplay || song.artist || '';
  el.playbar.hidden = false;
  document.title = `${song.songname} — LodiStudios`;
}

/* Pull two colours out of the artwork for the background wash. */
const ambientCache = new Map();
function setAmbient(src) {
  if (ambientCache.has(src)) return applyAmbient(ambientCache.get(src));
  const img = new Image();
  img.crossOrigin = 'anonymous';
  img.onload = () => {
    try {
      const c = document.createElement('canvas');
      c.width = c.height = 12;
      const ctx = c.getContext('2d', { willReadFrequently: true });
      ctx.drawImage(img, 0, 0, 12, 12);
      const d = ctx.getImageData(0, 0, 12, 12).data;
      let r = 0, g = 0, b = 0, n = 0;
      for (let i = 0; i < d.length; i += 4) { r += d[i]; g += d[i + 1]; b += d[i + 2]; n++; }
      const rgb = [Math.round(r / n), Math.round(g / n), Math.round(b / n)];
      ambientCache.set(src, rgb);
      applyAmbient(rgb);
    } catch { /* tainted canvas — keep the default wash */ }
  };
  img.src = src;
}
function applyAmbient([r, g, b]) {
  el.ambient.style.background =
    `radial-gradient(60% 60% at 20% 10%, rgba(${r},${g},${b},0.45), transparent 70%),` +
    `radial-gradient(55% 55% at 85% 25%, rgba(${Math.round(r * 0.5)},${Math.round(g * 0.4)},${b},0.38), transparent 70%)`;
}

/* ---------- playback ---------- */

function playAt(orderPos) {
  if (!state.order.length) return;
  state.pos = ((orderPos % state.order.length) + state.order.length) % state.order.length;
  const song = current();
  if (!song) return;

  audio.src = song.songPath;
  audio.play().catch((err) => {
    if (err && err.name === 'NotAllowedError') toast('Tap play to start audio');
    else toast(`Could not play "${song.songname}"`);
  });
  paintHero(song);
  markCurrent();
  updateMediaSession(song);
}

function togglePlay() {
  if (state.pos === -1) { playAt(0); return; }
  if (audio.paused) audio.play().catch(() => toast('Playback blocked'));
  else audio.pause();
}

function next(auto = false) {
  if (!state.order.length) return;
  if (auto && state.repeat === 'one') { audio.currentTime = 0; audio.play(); return; }
  if (state.pos >= state.order.length - 1 && state.repeat === 'off' && auto) {
    audio.pause();
    audio.currentTime = 0;
    return;
  }
  playAt(state.pos + 1);
}

function prev() {
  if (audio.currentTime > 3) { audio.currentTime = 0; return; }
  playAt(state.pos - 1);
}

/* ---------- audio events (attached once) ---------- */

audio.addEventListener('timeupdate', () => {
  if (state.seeking) return;
  const d = audio.duration;
  if (Number.isFinite(d) && d > 0) {
    const pct = (audio.currentTime / d) * 100;
    el.seekFill.style.width = pct + '%';
    el.seek.setAttribute('aria-valuenow', String(Math.round(pct)));
    el.seek.setAttribute('aria-valuetext', `${fmtTime(audio.currentTime)} of ${fmtTime(d)}`);
  }
  el.timeNow.textContent = fmtTime(audio.currentTime);
  syncPosition();
});

audio.addEventListener('loadedmetadata', () => {
  el.timeTotal.textContent = fmtTime(audio.duration);
  const song = current();
  if (song && Number.isFinite(audio.duration)) {
    state.durations.set(song.songPath, audio.duration);
    const row = el.tracklist.querySelector(`.track[data-i="${state.order[state.pos]}"] .t-time`);
    if (row) row.textContent = fmtTime(audio.duration);
  }
});

audio.addEventListener('progress', () => {
  if (audio.buffered.length && audio.duration) {
    const end = audio.buffered.end(audio.buffered.length - 1);
    el.seekBuffer.style.width = (end / audio.duration) * 100 + '%';
  }
});

audio.addEventListener('play', () => {
  document.body.classList.add('is-playing');
  el.btnPlay.setAttribute('aria-label', 'Pause');
  const song = current();
  if (song) paintHero(song);
  markCurrent();
  if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
});

// iOS can drop the metadata when the source changes, so re-assert it once
// playback is genuinely under way.
audio.addEventListener('playing', () => {
  const song = current();
  if (song) updateMediaSession(song);
  syncPosition();
});

audio.addEventListener('pause', () => {
  document.body.classList.remove('is-playing');
  el.btnPlay.setAttribute('aria-label', 'Play');
  const song = current();
  if (song) paintHero(song);
  markCurrent();
  if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
});

audio.addEventListener('ended', () => next(true));

audio.addEventListener('error', () => {
  const song = current();
  toast(song ? `Couldn't load "${song.songname}"` : 'Audio error');
});

audio.addEventListener('volumechange', () => {
  el.volFill.style.width = (audio.muted ? 0 : audio.volume * 100) + '%';
  el.vol.setAttribute('aria-valuenow', String(Math.round(audio.volume * 100)));
  document.body.classList.toggle('is-muted', audio.muted || audio.volume === 0);
  savePrefs();
});

/* ---------- media session (lock screen / bluetooth) ---------- */

function updateMediaSession(song) {
  if (!('mediaSession' in navigator)) return;

  // The artwork is 512x512 on disk; declare its true size and give an
  // absolute URL, which several platforms require.
  const art = song.albumArtPath
    ? [{ src: new URL(song.albumArtPath, location.href).href, sizes: '512x512', type: 'image/jpeg' }]
    : [];

  navigator.mediaSession.metadata = new MediaMetadata({
    title: song.songname || 'Untitled',
    artist: song.artistDisplay || song.artist || 'Unknown artist',
    album: song.albumDisplay || song.album || '',
    artwork: art,
  });
}

function syncPosition() {
  if (!('mediaSession' in navigator) || !navigator.mediaSession.setPositionState) return;
  if (!Number.isFinite(audio.duration) || audio.duration <= 0) return;
  try {
    navigator.mediaSession.setPositionState({
      duration: audio.duration,
      playbackRate: audio.playbackRate,
      position: clamp(audio.currentTime, 0, audio.duration),
    });
  } catch { /* some browsers reject mid-seek updates */ }
}

if ('mediaSession' in navigator) {
  const handlers = {
    play: () => audio.play(),
    pause: () => audio.pause(),
    previoustrack: prev,
    nexttrack: () => next(false),
    seekbackward: (d) => { audio.currentTime = Math.max(0, audio.currentTime - (d.seekOffset || 10)); },
    seekforward: (d) => { audio.currentTime = Math.min(audio.duration || 0, audio.currentTime + (d.seekOffset || 10)); },
    seekto: (d) => { if (d.fastSeek && audio.fastSeek) audio.fastSeek(d.seekTime); else audio.currentTime = d.seekTime; },
    stop: () => { audio.pause(); audio.currentTime = 0; },
  };
  for (const [action, fn] of Object.entries(handlers)) {
    try { navigator.mediaSession.setActionHandler(action, fn); } catch { /* unsupported action */ }
  }
}

/* ---------- slider interaction (pointer + keyboard) ---------- */

function ratioFrom(evt, node) {
  const r = node.getBoundingClientRect();
  return clamp((evt.clientX - r.left) / r.width, 0, 1);
}

function wireSlider(node, { onScrub, onCommit, onKey }) {
  let dragging = false;

  node.addEventListener('pointerdown', (e) => {
    dragging = true;
    node.classList.add('dragging');
    node.setPointerCapture(e.pointerId);
    onScrub(ratioFrom(e, node));
  });
  node.addEventListener('pointermove', (e) => { if (dragging) onScrub(ratioFrom(e, node)); });
  const end = (e) => {
    if (!dragging) return;
    dragging = false;
    node.classList.remove('dragging');
    onCommit(ratioFrom(e, node));
  };
  node.addEventListener('pointerup', end);
  node.addEventListener('pointercancel', end);
  node.addEventListener('keydown', onKey);
}

wireSlider(el.seek, {
  onScrub: (r) => {
    state.seeking = true;
    el.seekFill.style.width = r * 100 + '%';
    if (Number.isFinite(audio.duration)) el.timeNow.textContent = fmtTime(r * audio.duration);
  },
  onCommit: (r) => {
    if (Number.isFinite(audio.duration)) audio.currentTime = r * audio.duration;
    state.seeking = false;
  },
  onKey: (e) => {
    const step = e.shiftKey ? 30 : 5;
    if (e.key === 'ArrowRight') { audio.currentTime = Math.min(audio.duration || 0, audio.currentTime + step); e.preventDefault(); }
    if (e.key === 'ArrowLeft')  { audio.currentTime = Math.max(0, audio.currentTime - step); e.preventDefault(); }
  },
});

wireSlider(el.vol, {
  onScrub: (r) => { audio.muted = false; audio.volume = r; },
  onCommit: (r) => { audio.volume = r; },
  onKey: (e) => {
    if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { audio.volume = clamp(audio.volume + 0.05, 0, 1); e.preventDefault(); }
    if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { audio.volume = clamp(audio.volume - 0.05, 0, 1); e.preventDefault(); }
  },
});

/* ---------- controls ---------- */

el.btnPlay.onclick = togglePlay;
el.btnNext.onclick = () => next(false);
el.btnPrev.onclick = prev;
el.heroPlay.onclick = togglePlay;
el.btnMute.onclick = () => { audio.muted = !audio.muted; };

el.btnShuffle.onclick = () => {
  state.shuffle = !state.shuffle;
  el.btnShuffle.setAttribute('aria-pressed', String(state.shuffle));
  rebuildOrder();
  savePrefs();
  toast(state.shuffle ? 'Shuffle on' : 'Shuffle off');
};

el.heroShuffle.onclick = () => {
  if (!state.queue.length) return;
  state.shuffle = true;
  el.btnShuffle.setAttribute('aria-pressed', 'true');
  rebuildOrder();
  savePrefs();
  playAt(0);
};

el.btnRepeat.onclick = () => {
  state.repeat = state.repeat === 'off' ? 'all' : state.repeat === 'all' ? 'one' : 'off';
  el.btnRepeat.setAttribute('aria-pressed', String(state.repeat !== 'off'));
  el.repeatOne.hidden = state.repeat !== 'one';
  savePrefs();
  toast(`Repeat ${state.repeat}`);
};

el.tracklist.addEventListener('click', (e) => {
  const row = e.target.closest('.track');
  if (!row) return;
  const qi = Number(row.dataset.i);
  const op = state.order.indexOf(qi);
  if (op === state.pos && !audio.paused) audio.pause();
  else if (op === state.pos) audio.play();
  else playAt(op);
});

el.tracklist.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' && e.key !== ' ') return;
  const row = e.target.closest('.track');
  if (!row) return;
  e.preventDefault();
  row.click();
});

let searchTimer;
el.search.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => { state.search = el.search.value; render(); }, 140);
});

document.addEventListener('keydown', (e) => {
  const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName);
  if (typing) {
    if (e.key === 'Escape') { el.search.value = ''; state.search = ''; render(); el.search.blur(); }
    return;
  }
  switch (e.key) {
    case ' ':          e.preventDefault(); togglePlay(); break;
    case 'ArrowRight': if (e.altKey) next(false); else audio.currentTime += 5; break;
    case 'ArrowLeft':  if (e.altKey) prev(); else audio.currentTime -= 5; break;
    case 'ArrowUp':    e.preventDefault(); audio.volume = clamp(audio.volume + 0.05, 0, 1); break;
    case 'ArrowDown':  e.preventDefault(); audio.volume = clamp(audio.volume - 0.05, 0, 1); break;
    case 'm': case 'M': audio.muted = !audio.muted; break;
    case 's': case 'S': el.btnShuffle.click(); break;
    case 'r': case 'R': el.btnRepeat.click(); break;
    case '/':          e.preventDefault(); el.search.focus(); break;
  }
});

/* ---------- duration prefetch ---------- */

async function loadDurations(songs) {
  const queue = [...songs];
  const worker = async () => {
    while (queue.length) {
      const song = queue.shift();
      if (state.durations.has(song.songPath)) continue;
      await new Promise((resolve) => {
        const probe = new Audio();
        probe.preload = 'metadata';
        const done = () => { probe.src = ''; resolve(); };
        probe.addEventListener('loadedmetadata', () => {
          if (Number.isFinite(probe.duration)) {
            state.durations.set(song.songPath, probe.duration);
            const i = state.queue.indexOf(song);
            if (i !== -1) {
              const cell = el.tracklist.querySelector(`.track[data-i="${i}"] .t-time`);
              if (cell) cell.textContent = fmtTime(probe.duration);
            }
          }
          done();
        }, { once: true });
        probe.addEventListener('error', done, { once: true });
        probe.src = song.songPath;
      });
    }
  };
  await Promise.all([worker(), worker(), worker()]);
}

/* ---------- boot ---------- */

document.body.appendChild(audio);

el.btnShuffle.setAttribute('aria-pressed', String(state.shuffle));
el.btnRepeat.setAttribute('aria-pressed', String(state.repeat !== 'off'));
el.repeatOne.hidden = state.repeat !== 'one';
el.volFill.style.width = (audio.muted ? 0 : audio.volume * 100) + '%';
document.body.classList.toggle('is-muted', audio.muted || audio.volume === 0);

fetch(INDEX_URL, { cache: 'no-cache' })
  .then((res) => {
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    return res.json();
  })
  .then((data) => {
    if (!Array.isArray(data)) throw new Error('index.json is not a list');
    state.all = data.filter((s) => s && s.songPath);
    if (!state.all.length) throw new Error('no tracks found');
    renderFilters();
    render();
    loadDurations(state.all);
  })
  .catch((err) => {
    el.tracklist.innerHTML = '';
    el.empty.hidden = false;
    el.empty.textContent = `Couldn't load the catalogue: ${err.message}`;
  });

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/mediaplayer/serviceWorker.js').catch(() => { /* offline mode unavailable */ });
  });
}
