/* ==========================================================================
   CARAOKE PHONE & WIDGET SIMULATOR (100% SWIFT CODE MIRROR ENGINE)
   ========================================================================== */

const TRACKS = [
  {
    id: "demo",
    title: "Road Trip Anthem",
    artist: "Cibul & Njun",
    durationMs: 36000,
    coverImg: "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=200&auto=format&fit=crop&q=80",
    coverColor: "#FF8A00",
    lyrics: [
      { ms: 0, text: "The dashboard hums, the headlights glow" },
      { ms: 3000, text: "Two furry friends are in the know" },
      { ms: 6000, text: "Cibul the silver, first to sing" },
      { ms: 9000, text: "A puddle of wet food — the king" },
      { ms: 12000, text: "Njun stays out, the roads are long" },
      { ms: 15000, text: "But every chorus brings him home" },
      { ms: 18000, text: "Sing the lines that pass the time" },
      { ms: 21000, text: "Car-oke rhythm, hill and climb" },
      { ms: 24000, text: "The words come easy, line by line" },
      { ms: 27000, text: "Headlights, high beams, yours and mine" },
      { ms: 30000, text: "Take the wheel and take the night" },
      { ms: 33000, text: "Road trip verses, burning bright" }
    ]
  },
  {
    id: "cruel-summer",
    title: "Cruel Summer",
    artist: "Taylor Swift",
    durationMs: 178000,
    coverImg: "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&auto=format&fit=crop&q=80",
    coverColor: "#E05A7B",
    lyrics: [
      { ms: 0, text: "Fever dream high in the quiet of the night" },
      { ms: 4000, text: "You know that I caught it" },
      { ms: 8000, text: "Bad, bad boy, shiny toy with a price" },
      { ms: 12000, text: "You know that I bought it" },
      { ms: 16000, text: "Killing me slow, out the window" },
      { ms: 20000, text: "I'm always waiting for you to be waiting below" },
      { ms: 24000, text: "Devils roll the dice, angels roll their eyes" },
      { ms: 28000, text: "What doesn't kill me makes me want you more" },
      { ms: 32000, text: "And it's new, the shape of your body" },
      { ms: 36000, text: "It's blue, the feeling I've got" },
      { ms: 40000, text: "And it's ooh, whoa, oh" },
      { ms: 44000, text: "It's a cruel summer!" }
    ]
  },
  {
    id: "starboy",
    title: "Starboy",
    artist: "The Weeknd ft. Daft Punk",
    durationMs: 230000,
    coverImg: "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&auto=format&fit=crop&q=80",
    coverColor: "#D61828",
    lyrics: [
      { ms: 0, text: "I'm tryna put you in the worst mood, ah" },
      { ms: 4000, text: "P1 cleaner than your church shoes, ah" },
      { ms: 8000, text: "Milli point two just to hurt you, ah" },
      { ms: 12000, text: "All red Lamb' just to tease you, ah" },
      { ms: 16000, text: "None of these toys on lease too, ah" },
      { ms: 20000, text: "Made your whole year in a week too, yah" },
      { ms: 24000, text: "Main bitch out your league too, ah" },
      { ms: 28000, text: "Side bitch out of your league too, ah" },
      { ms: 32000, text: "Look what you've done" },
      { ms: 36000, text: "I'm a motherfuckin' starboy" }
    ]
  }
];

const State = {
  trackIdx: 0,
  isPlaying: true,
  positionMs: 0,
  speed: 1.0,
  status: "playing", // playing | paused | loading | noLyrics | stale
  rideModeOn: true,
  activeSource: "appleMusic", // appleMusic | spotify
  appearance: "dark",
  selectedPlan: "yearly", // yearly | monthly | lifetime
  widgetTheme: "artwork",  // artwork | pitchBlack | simpleSlate | ivoryWhite
  widgetCover: "vinyl",    // picture | vinyl
  showWidgetTips: false
};

let timer = null;

function startClock() {
  if (timer) clearInterval(timer);
  timer = setInterval(() => {
    if (!State.isPlaying || State.status !== "playing") return;
    const track = TRACKS[State.trackIdx];
    State.positionMs += 100 * State.speed;
    if (State.positionMs >= track.durationMs) {
      State.positionMs = 0;
    }
    render();
  }, 100);
}

function formatTime(ms) {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

function getLines(track, ms) {
  const lines = track.lyrics;
  if (!lines || lines.length === 0) return { prev: "", cur: "", next: "", prev2: "", next2: "", idx: 0 };

  let idx = 0;
  for (let i = 0; i < lines.length; i++) {
    if (ms >= lines[i].ms) idx = i;
    else break;
  }

  return {
    prev: idx > 0 ? lines[idx - 1].text : "",
    cur: lines[idx].text,
    next: idx + 1 < lines.length ? lines[idx + 1].text : "",
    prev2: idx > 1 ? lines[idx - 2].text : "",
    next2: idx + 2 < lines.length ? lines[idx + 2].text : "",
    idx: idx
  };
}

function statusBadgeText() {
  if (State.status === "loading") return "Finding lyrics…";
  if (State.status === "noLyrics") return "No lyrics";
  if (State.status === "stale") return "Ride ended";
  return State.isPlaying ? "Playing" : "Paused";
}

function statusCurText(lines) {
  if (State.status === "loading") return "Finding lyrics…";
  if (State.status === "noLyrics") return "No lyrics found";
  if (State.status === "stale") return "Ride ended";
  return lines.cur;
}

function statusNextText(lines) {
  if (State.status === "loading") return "";
  if (State.status === "noLyrics") return "Try another song";
  if (State.status === "stale") return "";
  return lines.next;
}

function render() {
  const track = TRACKS[State.trackIdx];
  const progress = Math.min(1, Math.max(0, State.positionMs / track.durationMs));
  const lines = getLines(track, State.positionMs);

  // Scrubber & HUD
  const scrubber = document.getElementById("sim-scrubber");
  if (scrubber) scrubber.value = progress * 100;
  const timeCur = document.getElementById("sim-time-cur");
  if (timeCur) timeCur.textContent = formatTime(State.positionMs);

  // Dynamic Island pill (always visible on iPhone chrome)
  const pillText = document.getElementById("island-pill-text");
  if (pillText) pillText.textContent = State.rideModeOn ? lines.cur : "Ride off";

  // 1. Home Screen Player Card (LyricTileView, surface .home)
  const homeCardId = document.getElementById("home-card-id");
  const homeCardBadge = document.getElementById("home-card-badge");
  const homeCardPrev = document.getElementById("home-card-prev");
  const homeCardCur = document.getElementById("home-card-cur");
  const homeCardNext = document.getElementById("home-card-next");
  const homeCardProg = document.getElementById("home-card-prog");

  if (homeCardId) homeCardId.textContent = `${track.title} — ${track.artist}`;
  if (homeCardBadge) homeCardBadge.textContent = statusBadgeText();

  if (homeCardPrev) homeCardPrev.textContent = (State.status === "loading" || State.status === "stale") ? "" : lines.prev;
  if (homeCardCur) homeCardCur.textContent = statusCurText(lines);
  if (homeCardNext) homeCardNext.textContent = statusNextText(lines);
  if (homeCardProg) homeCardProg.style.width = `${progress * 100}%`;

  // Home card status class for skeleton/empty states
  const homePlayerCard = document.querySelector(".home-player-card");
  if (homePlayerCard) {
    homePlayerCard.classList.remove("is-state-loading", "is-state-noLyrics", "is-state-stale");
    if (State.status === "loading") homePlayerCard.classList.add("is-state-loading");
    else if (State.status === "noLyrics") homePlayerCard.classList.add("is-state-noLyrics");
    else if (State.status === "stale") homePlayerCard.classList.add("is-state-stale");
  }
  const homeWidgetPrev = document.querySelector(".home-widget-preview-card");
  if (homeWidgetPrev) {
    homeWidgetPrev.classList.remove("is-state-loading", "is-state-noLyrics", "is-state-stale");
    if (State.status === "loading") homeWidgetPrev.classList.add("is-state-loading");
    else if (State.status === "noLyrics") homeWidgetPrev.classList.add("is-state-noLyrics");
    else if (State.status === "stale") homeWidgetPrev.classList.add("is-state-stale");
  }

  // 2. Home Screen Widget Preview (HomeWidgetPreview)
  const wPrevId = document.getElementById("widget-prev-id");
  const wPrevPrev = document.getElementById("widget-prev-prev");
  const wPrevCur = document.getElementById("widget-prev-cur");
  const wPrevNext = document.getElementById("widget-prev-next");
  const wPrevImg = document.getElementById("home-vinyl-img");
  const wPrevPlay = document.getElementById("widget-prev-play");
  const wDisc = document.getElementById("home-vinyl-disc");

  if (wPrevId) wPrevId.textContent = `${track.title} — ${track.artist}${State.activeSource === "spotify" ? " · Spotify" : ""}`;
  if (wPrevPrev) wPrevPrev.textContent = (State.status === "loading" || State.status === "stale") ? "" : lines.prev;
  if (wPrevCur) wPrevCur.textContent = statusCurText(lines);
  if (wPrevNext) wPrevNext.textContent = statusNextText(lines);
  if (wPrevImg) wPrevImg.src = track.coverImg;
  if (wPrevPlay) wPrevPlay.textContent = State.isPlaying ? "⏸" : "▶";
  if (wDisc) {
    if (State.isPlaying) wDisc.classList.remove("paused");
    else wDisc.classList.add("paused");
  }

  // 3. Floating Mini-Player
  const miniTitle = document.getElementById("mini-player-title");
  const miniDot = document.getElementById("mini-badge-dot");
  const miniSub = document.getElementById("mini-player-sub");
  const miniArt = document.getElementById("mini-player-art");
  const miniPlay = document.getElementById("mini-play");

  if (miniTitle) miniTitle.textContent = track.title;
  if (miniDot && miniSub) {
    if (State.activeSource === "appleMusic") {
      miniDot.className = "mini-badge-dot apple";
      miniSub.className = "mini-badge-text apple";
      miniSub.textContent = "Apple Music";
    } else {
      miniDot.className = "mini-badge-dot spotify";
      miniSub.className = "mini-badge-text spotify";
      miniSub.textContent = "Spotify";
    }
  }
  if (miniArt) miniArt.src = track.coverImg;
  if (miniPlay) miniPlay.textContent = State.isPlaying ? "⏸" : "▶";

  // 4. Fullscreen Lyrics Page
  const pageTitle = document.getElementById("page-title");
  const pageArtist = document.getElementById("page-artist");
  const stageSongTitle = document.getElementById("stage-song-title");
  const stageSongArtist = document.getElementById("stage-song-artist");
  const pageArt = document.getElementById("page-art");
  const pageProg = document.getElementById("page-prog-fill");
  const pageTimeCur = document.getElementById("page-time-cur");
  const pageTimeRem = document.getElementById("page-time-rem");
  const pageBtnPlay = document.getElementById("page-btn-play");

  if (pageTitle) pageTitle.textContent = track.title;
  if (pageArtist) pageArtist.textContent = track.artist;
  if (stageSongTitle) stageSongTitle.textContent = track.title;
  if (stageSongArtist) stageSongArtist.textContent = track.artist;
  if (pageArt) pageArt.src = track.coverImg;
  if (pageProg) pageProg.style.width = `${progress * 100}%`;
  if (pageTimeCur) pageTimeCur.textContent = formatTime(State.positionMs);
  if (pageTimeRem) pageTimeRem.textContent = `-${formatTime(Math.max(0, track.durationMs - State.positionMs))}`;
  if (pageBtnPlay) pageBtnPlay.textContent = State.isPlaying ? "⏸" : "▶";

  highlightActiveLyricsRow(lines.idx);

  // 5b. WidgetSettingsView live preview (if open)
  if (document.getElementById("modal-widget-settings")?.classList.contains("active")) {
    renderWidgetSettings();
  }

  // 6. Standalone Widgets View (Small, Medium, Large, Lock Screen, CarPlay, DI, StandBy)
  const sSmallTitle = document.getElementById("stand-small-title");
  const sSmallCur = document.getElementById("stand-small-cur");
  const sSmallNext = document.getElementById("stand-small-next");
  const sSmallNext2 = document.getElementById("stand-small-next2");
  const sSmallProg = document.getElementById("stand-small-prog");

  if (sSmallTitle) sSmallTitle.textContent = track.title;
  if (sSmallCur) sSmallCur.textContent = statusCurText(lines);
  if (sSmallNext) sSmallNext.textContent = statusNextText(lines);
  if (sSmallNext2) sSmallNext2.textContent = (State.status === "loading" || State.status === "stale" || State.status === "noLyrics") ? "" : lines.next2;
  if (sSmallProg) sSmallProg.style.width = `${progress * 100}%`;

  const sMedId = document.getElementById("stand-med-id");
  const sMedPrev = document.getElementById("stand-med-prev");
  const sMedCur = document.getElementById("stand-med-cur");
  const sMedNext = document.getElementById("stand-med-next");
  const sMedImg = document.getElementById("stand-med-img");
  const sMedPlay = document.getElementById("stand-med-play");
  const sMedDisc = document.getElementById("stand-med-disc");

  if (sMedId) sMedId.textContent = `${track.title} — ${track.artist}`;
  if (sMedPrev) sMedPrev.textContent = (State.status === "loading" || State.status === "stale") ? "" : lines.prev;
  if (sMedCur) sMedCur.textContent = statusCurText(lines);
  if (sMedNext) sMedNext.textContent = statusNextText(lines);
  if (sMedImg) sMedImg.src = track.coverImg;
  if (sMedPlay) sMedPlay.textContent = State.isPlaying ? "⏸" : "▶";
  if (sMedDisc) {
    if (State.isPlaying) sMedDisc.classList.remove("paused");
    else sMedDisc.classList.add("paused");
  }

  const sLrgCur = document.getElementById("stand-lrg-cur");
  const sLrgPrev = document.getElementById("stand-lrg-prev");
  const sLrgPrev2 = document.getElementById("stand-lrg-prev2");
  const sLrgNext = document.getElementById("stand-lrg-next");
  const sLrgArt = document.getElementById("stand-lrg-art");
  const sLrgTitle = document.getElementById("stand-lrg-title");
  const sLrgArtist = document.getElementById("stand-lrg-artist");
  const sLrgPlay = document.getElementById("stand-lrg-play");

  if (sLrgCur) sLrgCur.textContent = statusCurText(lines);
  if (sLrgPrev) sLrgPrev.textContent = (State.status === "loading" || State.status === "stale") ? "" : lines.prev;
  if (sLrgPrev2) sLrgPrev2.textContent = (State.status === "loading" || State.status === "stale") ? "" : lines.prev2;
  if (sLrgNext) sLrgNext.textContent = statusNextText(lines);
  if (sLrgArt) sLrgArt.src = track.coverImg;
  if (sLrgTitle) sLrgTitle.textContent = track.title;
  if (sLrgArtist) sLrgArtist.textContent = track.artist;
  if (sLrgPlay) sLrgPlay.textContent = State.isPlaying ? "⏸" : "▶";

  const sLockCur = document.getElementById("stand-lock-cur");
  const sLockPrev = document.getElementById("stand-lock-prev");
  const sLockNext = document.getElementById("stand-lock-next");
  const sLockProg = document.getElementById("stand-lock-prog");
  const sLockCurT = document.getElementById("stand-lock-cur-time");
  const sLockRemT = document.getElementById("stand-lock-rem-time");
  const sLockBadge = document.getElementById("stand-lock-badge");
  const lockBanner = document.querySelector(".standalone-lock-banner");

  if (sLockPrev) sLockPrev.textContent = (State.status === "loading" || State.status === "stale") ? "" : lines.prev;
  if (sLockCur) sLockCur.textContent = statusCurText(lines);
  if (sLockNext) sLockNext.textContent = statusNextText(lines);
  if (sLockProg) sLockProg.style.width = `${progress * 100}%`;
  if (sLockCurT) sLockCurT.textContent = formatTime(State.positionMs);
  if (sLockRemT) sLockRemT.textContent = `-${formatTime(Math.max(0, track.durationMs - State.positionMs))}`;
  if (sLockBadge) sLockBadge.textContent = statusBadgeText();
  if (lockBanner) {
    lockBanner.classList.remove("is-state-loading", "is-state-noLyrics", "is-state-stale");
    if (State.status === "loading") lockBanner.classList.add("is-state-loading");
    else if (State.status === "noLyrics") lockBanner.classList.add("is-state-noLyrics");
    else if (State.status === "stale") lockBanner.classList.add("is-state-stale");
  }

  // 7. CarPlay supplemental tile
  const carTitle = document.getElementById("stand-carplay-title");
  const carArtist = document.getElementById("stand-carplay-artist");
  const carCur = document.getElementById("stand-carplay-cur");
  const carProg = document.getElementById("stand-carplay-prog");
  if (carTitle) carTitle.textContent = track.title;
  if (carArtist) carArtist.textContent = track.artist;
  if (carCur) carCur.textContent = statusCurText(lines);
  if (carProg) carProg.style.width = `${progress * 100}%`;

  // 8. Dynamic Island variants
  const diLeading = document.getElementById("di-compact-leading");
  const diTrailing = document.getElementById("di-compact-trailing");
  const diMinText = document.getElementById("di-minimal-text");
  const diExpLead = document.getElementById("di-exp-leading");
  const diExpCur = document.getElementById("di-exp-cur");
  const diExpNext = document.getElementById("di-exp-next");
  const diExpProg = document.getElementById("di-exp-prog");

  if (diLeading) diLeading.textContent = State.isPlaying ? "🎵" : "⏸";
  if (diTrailing) diTrailing.textContent = State.rideModeOn ? (statusCurText(lines).slice(0, 14) || "Caraoke") : "Ride off";
  if (diMinText) diMinText.textContent = State.rideModeOn ? (statusCurText(lines).slice(0, 6) || "Caraoke") : "Off";
  if (diExpLead) diExpLead.textContent = State.isPlaying ? "⏸" : "▶";
  if (diExpCur) diExpCur.textContent = statusCurText(lines);
  if (diExpNext) diExpNext.textContent = statusNextText(lines);
  if (diExpProg) diExpProg.style.width = `${progress * 100}%`;

  // 9. StandBy mode
  const sbLyric = document.getElementById("standby-lyric");
  const sbNext = document.getElementById("standby-next");
  const sbTitle = document.getElementById("standby-title");
  const sbArtist = document.getElementById("standby-artist");
  if (sbLyric) sbLyric.textContent = statusCurText(lines);
  if (sbNext) sbNext.textContent = statusNextText(lines);
  if (sbTitle) sbTitle.textContent = track.title;
  if (sbArtist) sbArtist.textContent = track.artist;

  // 10. Mirror source switch into Settings sheet + source rows (sync)
  const appleSub = document.getElementById("source-sub-apple");
  const spotifySub = document.getElementById("source-sub-spotify");
  const appleCheck = document.getElementById("source-check-apple");
  const spotifyCheck = document.getElementById("source-check-spotify");
  if (State.activeSource === "appleMusic") {
    if (appleCheck) appleCheck.style.display = "block";
    if (spotifyCheck) spotifyCheck.style.display = "none";
    if (appleSub) { appleSub.textContent = "Active source"; appleSub.className = "source-subtitle connected"; }
    if (spotifySub) { spotifySub.textContent = "Connected (tap to switch)"; spotifySub.className = "source-subtitle"; }
  } else {
    if (appleCheck) appleCheck.style.display = "none";
    if (spotifyCheck) spotifyCheck.style.display = "block";
    if (appleSub) { appleSub.textContent = "Connected (tap to switch)"; appleSub.className = "source-subtitle"; }
    if (spotifySub) { spotifySub.textContent = "Active source"; spotifySub.className = "source-subtitle connected"; }
  }
  document.querySelectorAll("#modal-settings .g-row").forEach(row => {
    const label = row.querySelector(".g-label")?.textContent?.trim();
    const val = row.querySelector(".g-value");
    if (!val) return;
    if (label === "Apple Music") val.textContent = State.activeSource === "appleMusic" ? "Active source" : "Connected";
    if (label === "Spotify") val.textContent = State.activeSource === "spotify" ? "Active source" : "Custom Client ID configured";
  });
}

function renderWidgetSettings() {
  const track = TRACKS[State.trackIdx];
  const lines = getLines(track, State.positionMs);
  const preview = document.getElementById("ws-preview");
  if (!preview) return;

  // Theme application: 4 cases map to .theme-pitchBlack, .theme-simpleSlate,
  // .theme-ivoryWhite; "artwork" = default gradient (no class).
  preview.classList.remove("theme-pitchBlack", "theme-simpleSlate", "theme-ivoryWhite");
  if (State.widgetTheme !== "artwork") {
    preview.classList.add(`theme-${State.widgetTheme}`);
  }

  // 15pt typography (WidgetSettingsView preview: bold hero, lineLimit 3,
  // minimumScaleFactor 0.75) — distinct from the 18pt in-app LyricTileView.
  document.getElementById("ws-prev-id").textContent = `${track.title} — ${track.artist}`;
  document.getElementById("ws-prev-prev").textContent = lines.prev;
  document.getElementById("ws-prev-cur").textContent = lines.cur;
  document.getElementById("ws-prev-next").textContent = lines.next;
  document.getElementById("ws-prev-play").textContent = State.isPlaying ? "⏸" : "▶";

  // Cover style: 126x126 vinyl (6 rings, 88pt label, 7pt spindle) or
  // 110x110 picture (cornerRadius 14, white opacity 0.12 border).
  const slot = document.getElementById("ws-prev-cover-slot");
  if (!slot) return;
  if (State.widgetCover === "vinyl") {
    slot.innerHTML = `
      <div class="real-vinyl-disc" id="ws-vinyl">
        <div class="vinyl-ring-1"></div>
        <div class="vinyl-ring-2"></div>
        <div class="vinyl-ring-3"></div>
        <div class="ws-vinyl-label"><img src="${track.coverImg}" alt="Disc" /></div>
        <div class="vinyl-spindle-hole"></div>
      </div>`;
    const v = document.getElementById("ws-vinyl");
    if (v && !State.isPlaying) v.classList.add("paused");
  } else {
    slot.innerHTML = `<img class="ws-cover-picture" src="${track.coverImg}" alt="Art" />`;
  }
}

function renderLyricsStage() {
  const container = document.getElementById("stage-lines-container");
  if (!container) return;
  const track = TRACKS[State.trackIdx];
  container.innerHTML = "";

  track.lyrics.forEach((l, idx) => {
    const row = document.createElement("div");
    row.className = "page-lyric-row";
    row.id = `stage-row-${idx}`;
    row.textContent = l.text;
    row.onclick = () => {
      State.positionMs = l.ms;
      render();
    };
    container.appendChild(row);
  });
}

function highlightActiveLyricsRow(currentIdx) {
  const track = TRACKS[State.trackIdx];
  const container = document.getElementById("stage-lines-container");
  if (!container) return;

  const rows = container.querySelectorAll(".page-lyric-row");
  rows.forEach((r, idx) => {
    if (idx < currentIdx) {
      r.className = "page-lyric-row past";
    } else if (idx === currentIdx) {
      r.className = "page-lyric-row active";
      r.scrollIntoView({ behavior: "smooth", block: "center" });
    } else {
      r.className = "page-lyric-row";
    }
  });
}

function setupEvents() {
  // View Switcher (iPhone vs All Widgets)
  document.querySelectorAll(".sim-view-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".sim-view-btn").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      const target = btn.dataset.view;

      document.getElementById("view-phone").style.display = target === "phone" ? "flex" : "none";
      document.getElementById("view-widgets").style.display = target === "widgets" ? "flex" : "none";
    });
  });

  // Track Selector
  document.getElementById("select-track")?.addEventListener("change", (e) => {
    State.trackIdx = parseInt(e.target.value, 10);
    State.positionMs = 0;
    renderLyricsStage();
    render();
  });

  // Transport
  const togglePlay = () => {
    State.isPlaying = !State.isPlaying;
    const btn = document.getElementById("btn-play-pause");
    if (btn) btn.textContent = State.isPlaying ? "⏸" : "▶";
    render();
  };

  document.getElementById("btn-play-pause")?.addEventListener("click", togglePlay);
  document.getElementById("mini-play")?.addEventListener("click", (e) => {
    e.stopPropagation();
    togglePlay();
  });
  document.getElementById("page-btn-play")?.addEventListener("click", togglePlay);
  document.getElementById("widget-prev-play")?.addEventListener("click", togglePlay);

  const nextSong = () => {
    State.trackIdx = (State.trackIdx + 1) % TRACKS.length;
    State.positionMs = 0;
    const sel = document.getElementById("select-track");
    if (sel) sel.value = State.trackIdx;
    renderLyricsStage();
    render();
  };
  const prevSong = () => {
    State.trackIdx = (State.trackIdx - 1 + TRACKS.length) % TRACKS.length;
    State.positionMs = 0;
    const sel = document.getElementById("select-track");
    if (sel) sel.value = State.trackIdx;
    renderLyricsStage();
    render();
  };

  document.getElementById("btn-next")?.addEventListener("click", nextSong);
  document.getElementById("mini-next")?.addEventListener("click", (e) => { e.stopPropagation(); nextSong(); });
  document.getElementById("page-btn-next")?.addEventListener("click", nextSong);

  document.getElementById("btn-prev")?.addEventListener("click", prevSong);
  document.getElementById("mini-prev")?.addEventListener("click", (e) => { e.stopPropagation(); prevSong(); });
  document.getElementById("page-btn-prev")?.addEventListener("click", prevSong);

  // Scrubber
  document.getElementById("sim-scrubber")?.addEventListener("input", (e) => {
    const track = TRACKS[State.trackIdx];
    State.positionMs = (parseFloat(e.target.value) / 100) * track.durationMs;
    render();
  });

  // State Override
  document.getElementById("select-status")?.addEventListener("change", (e) => {
    State.status = e.target.value;
    render();
  });

  // Theme Toggle (Dark OLED / Light)
  document.getElementById("btn-toggle-theme")?.addEventListener("click", () => {
    State.appearance = State.appearance === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-appearance", State.appearance);
  });

  // Navigation to Modals
  document.getElementById("btn-card-open-lyrics")?.addEventListener("click", () => {
    document.getElementById("modal-lyrics-page")?.classList.add("active");
    renderLyricsStage();
  });
  document.getElementById("floating-mini-player")?.addEventListener("click", () => {
    document.getElementById("modal-lyrics-page")?.classList.add("active");
    renderLyricsStage();
  });
  document.getElementById("btn-close-lyrics")?.addEventListener("click", () => {
    document.getElementById("modal-lyrics-page")?.classList.remove("active");
  });

  document.getElementById("btn-open-settings")?.addEventListener("click", () => {
    document.getElementById("modal-settings")?.classList.add("active");
  });
  document.getElementById("btn-close-settings")?.addEventListener("click", () => {
    document.getElementById("modal-settings")?.classList.remove("active");
  });

  document.getElementById("settings-plus-card")?.addEventListener("click", () => {
    document.getElementById("modal-paywall")?.classList.add("active");
  });
  document.getElementById("btn-close-paywall")?.addEventListener("click", () => {
    document.getElementById("modal-paywall")?.classList.remove("active");
  });

  // ========================================================================
  // WIDGET SETTINGS (WidgetSettingsView.swift)
  // ========================================================================
  document.getElementById("btn-open-widget-settings")?.addEventListener("click", (e) => {
    // Don't trigger when clicking the inner preview card itself (let it act
    // as visual content). Real Swift opens this whole section via tap.
    e.stopPropagation();
    document.getElementById("modal-widget-settings")?.classList.add("active");
    renderWidgetSettings();
  });
  document.getElementById("btn-close-widget-settings")?.addEventListener("click", () => {
    document.getElementById("modal-widget-settings")?.classList.remove("active");
  });

  // Theme swatches (4 cases: artwork, pitchBlack, simpleSlate, ivoryWhite)
  document.querySelectorAll(".theme-swatch").forEach(btn => {
    btn.addEventListener("click", () => {
      State.widgetTheme = btn.dataset.theme;
      document.querySelectorAll(".theme-swatch").forEach(b => b.classList.remove("selected"));
      btn.classList.add("selected");
      renderWidgetSettings();
    });
  });

  // Segmented Cover style picker (Picture / Vinyl Disc)
  document.querySelectorAll(".seg-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      State.widgetCover = btn.dataset.cover;
      document.querySelectorAll(".seg-btn").forEach(b => b.classList.remove("selected"));
      btn.classList.add("selected");
      renderWidgetSettings();
    });
  });

  // Tips toggle
  document.getElementById("btn-toggle-tips")?.addEventListener("click", () => {
    State.showWidgetTips = !State.showWidgetTips;
    const panel = document.getElementById("widget-tips-panel");
    const label = document.getElementById("tips-toggle-label");
    if (panel) panel.style.display = State.showWidgetTips ? "flex" : "none";
    if (label) label.textContent = State.showWidgetTips
      ? "Hide real-time update tips"
      : "Make widgets update in real time";
  });

  // Music Source Selectors (exact HomeView.swift behavior)
  function setActiveSource(src) {
    State.activeSource = src;
    const appleSub = document.getElementById("source-sub-apple");
    const spotifySub = document.getElementById("source-sub-spotify");
    const appleCheck = document.getElementById("source-check-apple");
    const spotifyCheck = document.getElementById("source-check-spotify");
    if (src === "appleMusic") {
      if (appleCheck) appleCheck.style.display = "block";
      if (spotifyCheck) spotifyCheck.style.display = "none";
      if (appleSub) { appleSub.textContent = "Active source"; appleSub.className = "source-subtitle connected"; }
      if (spotifySub) { spotifySub.textContent = "Connected (tap to switch)"; spotifySub.className = "source-subtitle"; }
    } else {
      if (appleCheck) appleCheck.style.display = "none";
      if (spotifyCheck) spotifyCheck.style.display = "block";
      if (appleSub) { appleSub.textContent = "Connected (tap to switch)"; appleSub.className = "source-subtitle"; }
      if (spotifySub) { spotifySub.textContent = "Active source"; spotifySub.className = "source-subtitle connected"; }
    }
    // Mirror into Settings sheet (id selectors by data attrs not present; query by label)
    document.querySelectorAll("#modal-settings .g-row").forEach(row => {
      const label = row.querySelector(".g-label")?.textContent?.trim();
      const val = row.querySelector(".g-value");
      if (label === "Apple Music") val.textContent = src === "appleMusic" ? "Active source" : "Connected";
      if (label === "Spotify") val.textContent = src === "spotify" ? "Active source" : "Custom Client ID configured";
    });
    render();
  }

  document.getElementById("source-row-apple")?.addEventListener("click", () => setActiveSource("appleMusic"));
  document.getElementById("source-row-spotify")?.addEventListener("click", () => setActiveSource("spotify"));

  // Ride Mode Toggle Switch
  document.getElementById("toggle-ride-mode")?.addEventListener("click", () => {
    State.rideModeOn = !State.rideModeOn;
    document.getElementById("toggle-ride-mode")?.classList.toggle("off", !State.rideModeOn);
  });

  // Paywall Tier Selectors (Exact PaywallView.swift ctaButtonText logic)
  const tiers = [
    { id: "tier-yearly", plan: "yearly", cta: "Subscribe Yearly" },
    { id: "tier-monthly", plan: "monthly", cta: "Start 3-Day Free Trial" },
    { id: "tier-lifetime", plan: "lifetime", cta: "Get Lifetime Access" }
  ];
  tiers.forEach(t => {
    document.getElementById(t.id)?.addEventListener("click", () => {
      document.querySelectorAll(".paywall-tier-card").forEach(c => c.classList.remove("selected"));
      document.getElementById(t.id)?.classList.add("selected");
      State.selectedPlan = t.plan;
      document.getElementById("paywall-cta").textContent = t.cta;
    });
  });

  // Help & How to docs
  document.getElementById("btn-open-docs")?.addEventListener("click", () => {
    window.open("https://caraoke.live/docs", "_blank");
  });
  document.getElementById("btn-howto")?.addEventListener("click", () => {
    window.open("https://caraoke.live/docs", "_blank");
  });
}

window.addEventListener("DOMContentLoaded", () => {
  setupEvents();
  renderLyricsStage();
  render();
  startClock();
});
