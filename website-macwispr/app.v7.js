/* =========================================================
   f*ckwisprflow — motion + race + speed flex
   Performance-first: content always visible; motion is optional polish
   ========================================================= */

const yearEl = document.getElementById("y");
if (yearEl) yearEl.textContent = String(new Date().getFullYear());

const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const coarse = window.matchMedia("(hover: none), (max-width: 820px)").matches;
const hasGSAP = typeof gsap !== "undefined";
const hasST = typeof ScrollTrigger !== "undefined";
const hasLenis = typeof Lenis !== "undefined";

/* Pause SMIL marquee animations when motion is reduced */
if (reduced) {
  document.querySelectorAll(".bg-marquee animate").forEach((anim) => {
    try {
      anim.endElement();
    } catch (_) {
      /* ignore */
    }
    anim.remove();
  });
  document.querySelectorAll(".bg-marquee text").forEach((textEl) => {
    textEl.setAttribute("x", "-900");
  });
}

/* ---------- Smooth scroll (Lenis) — desktop only, light settings ---------- */
let lenis = null;
if (!reduced && hasLenis && !coarse) {
  lenis = new Lenis({
    duration: 0.95,
    easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
    smoothWheel: true,
    touchMultiplier: 1,
    autoRaf: true,
    syncTouch: false,
  });
  // Keep ScrollTrigger in sync when Lenis drives scroll
  if (hasGSAP && hasST) {
    lenis.on("scroll", ScrollTrigger.update);
  }
}
if (hasGSAP && hasST) {
  gsap.registerPlugin(ScrollTrigger);
  // Prefer native scroll root for ST (more stable than custom scroller)
  ScrollTrigger.config({ ignoreMobileResize: true });
}

/* ---------- Scroll progress bar (rAF-throttled) ---------- */
const progressEl = document.getElementById("scroll-progress");
let progressRaf = 0;
function updateProgress() {
  if (!progressEl) return;
  const h = document.documentElement;
  const max = h.scrollHeight - h.clientHeight;
  const p = max > 0 ? (window.scrollY || h.scrollTop) / max : 0;
  progressEl.style.width = `${Math.min(100, p * 100)}%`;
  progressRaf = 0;
}
function requestProgress() {
  if (progressRaf) return;
  progressRaf = requestAnimationFrame(updateProgress);
}
window.addEventListener("scroll", requestProgress, { passive: true });
if (lenis) lenis.on("scroll", requestProgress);
updateProgress();

/* ---------- Living background: orbs + sparse sparks (desktop only) ---------- */
function initBackground() {
  const o1 = document.querySelector(".o1");
  const o2 = document.querySelector(".o2");
  const o3 = document.querySelector(".o3");
  const canvas = document.getElementById("spark");
  if (reduced) return;

  if (hasGSAP && o1 && o2 && o3 && !coarse) {
    gsap.to(o1, {
      x: 28,
      y: 20,
      duration: 14,
      repeat: -1,
      yoyo: true,
      ease: "sine.inOut",
      force3D: true,
    });
    gsap.to(o2, {
      x: -24,
      y: 30,
      duration: 16,
      repeat: -1,
      yoyo: true,
      ease: "sine.inOut",
      delay: 0.5,
      force3D: true,
    });
    gsap.to(o3, {
      x: 18,
      y: -22,
      duration: 18,
      repeat: -1,
      yoyo: true,
      ease: "sine.inOut",
      delay: 1,
      force3D: true,
    });
  }

  // Skip canvas particles on mobile / reduced motion / missing canvas
  if (coarse || !canvas || !canvas.getContext) {
    if (canvas) canvas.style.display = "none";
    return;
  }

  const ctx = canvas.getContext("2d", { alpha: true, desynchronized: true });
  let w = 0;
  let h = 0;
  let particles = [];
  let rafId = 0;
  let running = true;
  let last = 0;
  const dprCap = Math.min(window.devicePixelRatio || 1, 1.5);

  function resize() {
    const cssW = window.innerWidth;
    const cssH = window.innerHeight;
    w = canvas.width = Math.floor(cssW * dprCap);
    h = canvas.height = Math.floor(cssH * dprCap);
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    const count = cssW < 900 ? 16 : 28;
    particles = Array.from({ length: count }, () => ({
      x: Math.random() * w,
      y: Math.random() * h,
      r: 0.5 + Math.random() * 1.4,
      vx: (Math.random() - 0.5) * 0.12,
      vy: -0.04 - Math.random() * 0.16,
      a: 0.12 + Math.random() * 0.28,
    }));
  }

  function tick(ts) {
    if (!running) return;
    // ~30fps is plenty for ambient dust
    if (ts - last < 32) {
      rafId = requestAnimationFrame(tick);
      return;
    }
    last = ts;
    ctx.clearRect(0, 0, w, h);
    for (const p of particles) {
      p.x += p.vx * dprCap;
      p.y += p.vy * dprCap;
      if (p.y < -10) p.y = h + 10;
      if (p.x < -10) p.x = w + 10;
      if (p.x > w + 10) p.x = -10;
      ctx.beginPath();
      ctx.fillStyle = `rgba(20,18,15,${p.a})`;
      ctx.arc(p.x, p.y, p.r * dprCap, 0, Math.PI * 2);
      ctx.fill();
    }
    rafId = requestAnimationFrame(tick);
  }

  let resizeT = 0;
  function onResize() {
    clearTimeout(resizeT);
    resizeT = setTimeout(resize, 120);
  }

  resize();
  window.addEventListener("resize", onResize, { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      running = false;
      cancelAnimationFrame(rafId);
    } else {
      running = true;
      last = 0;
      rafId = requestAnimationFrame(tick);
    }
  });
  rafId = requestAnimationFrame(tick);
}

/* ---------- Reveals: never blank — pending only after motion is armed ---------- */
function showReveal(el) {
  if (!el || el.dataset.revealed === "1") return;
  el.dataset.revealed = "1";
  el.classList.remove("is-pending");
  el.classList.add("is-in");

  if (reduced || !hasGSAP) return;

  // Light polish only (CSS already handles most of it via transition)
  const delay = parseFloat(el.dataset.delay || "0");
  if (delay > 0) {
    el.style.transitionDelay = `${delay}s`;
  }
}

function initMotion() {
  if (reduced || !hasGSAP) {
    document.querySelectorAll(".reveal").forEach((el) => {
      el.classList.add("is-in");
      el.dataset.revealed = "1";
    });
    return;
  }

  // Enable pending-hide only now that JS is alive
  document.documentElement.classList.add("motion-on");

  // Hero is never pending — always painted (LCP)
  document.querySelectorAll(".hero .reveal").forEach((el) => {
    el.classList.add("is-in");
    el.dataset.revealed = "1";
  });

  // Soft hero entrance (from current state → no FOUC blank)
  const heroLines = document.querySelectorAll(".hero h1 .line");
  const heroRest = document.querySelectorAll(
    ".hero .eyebrow, .hero .lede, .hero .hero-actions, .hero .hero-chips"
  );
  if (heroLines.length) {
    gsap.from(heroLines, {
      y: 36,
      opacity: 0.001,
      duration: 0.85,
      stagger: 0.1,
      ease: "power3.out",
      delay: 0.05,
      clearProps: "transform,opacity",
    });
  }
  if (heroRest.length) {
    gsap.from(heroRest, {
      y: 16,
      opacity: 0.001,
      duration: 0.65,
      stagger: 0.05,
      ease: "power3.out",
      delay: 0.18,
      clearProps: "transform,opacity",
    });
  }
  const toReveal = [...document.querySelectorAll(".reveal")].filter(
    (el) => !el.closest(".hero") && el.dataset.revealed !== "1"
  );
  toReveal.forEach((el) => el.classList.add("is-pending"));

  // Safety: never leave anything pending more than 1.2s
  setTimeout(() => {
    document.querySelectorAll(".reveal.is-pending").forEach(showReveal);
  }, 1200);

  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            showReveal(entry.target);
            io.unobserve(entry.target);
          }
        });
      },
      { root: null, rootMargin: "0px 0px -4% 0px", threshold: 0.08 }
    );
    toReveal.forEach((el) => io.observe(el));
  } else {
    toReveal.forEach(showReveal);
  }
}

/* ------------------------------------------------------------------ */
/* Race demo — bench-aligned: local <0.5s, Wispr Flow ~2–3s           */
/* ------------------------------------------------------------------ */

const RACE = {
  raw: "umm send the deck from yesterdays meeting",
  clean: "Send the deck from yesterday’s meeting.",
  fillers: ["umm"],
  localTargetMs: 420,
  flowMinMs: 2100,
  flowMaxMs: 2900,
};

const el = {
  root: document.getElementById("race-demo"),
  waveWrap: document.getElementById("race-wave-wrap"),
  wave: document.getElementById("race-wave"),
  waveLabel: document.getElementById("race-wave-label"),
  localText: document.getElementById("local-text"),
  cloudText: document.getElementById("cloud-text"),
  localStatus: document.getElementById("local-status"),
  cloudStatus: document.getElementById("cloud-status"),
  localBadge: document.getElementById("local-badge"),
  cloudBadge: document.getElementById("cloud-badge"),
  localLane: document.getElementById("lane-local"),
  cloudLane: document.getElementById("lane-cloud"),
  caption: document.getElementById("race-caption"),
  replay: document.getElementById("race-replay"),
};

/* Height sequences from Flow Lottie (23 bars) */
const FLOW_BARS = [
  [24.2, 28.8, 21.8, 24, 20.7, 26.9, 15.7, 13.7, 7.2, 11, 25, 33.8, 32.9, 9.5, 10.3, 31.5, 19.2, 3, 16.2, 19.3, 34, 22.5, 22.7, 25.1, 27.1, 13, 17.7, 25.7, 26.3, 33.3, 13.4, 10.9, 27.1, 10, 14.4, 3, 10.4, 5.6, 23.7, 15.2, 9.6, 3, 24.2],
  [22.7, 31.9, 34.5, 26.2, 30.5, 26.8, 15.4, 28.1, 11.7, 7, 24.2, 13, 47.8, 34.1, 31.1, 31.9, 2.4, 4, 42, 29.2, 26.7, 31, 13.4, 22.6, 19.8, 16.6, 36.4, 43, 43, 21.9, 6, 19.3, 5.9, 5.4, 3, 3, 14.5, 24.6, 20.7, 15.7, 24.5, 22.7],
  [14.2, 30.8, 16.7, 13.4, 21.2, 8.8, 21, 8.2, 4.9, 12.4, 17.4, 3, 27.7, 27.3, 21.2, 12.8, 17.6, 5.3, 5, 25.8, 31, 19.2, 20.1, 29.9, 12, 5.7, 22.2, 20.5, 31.7, 24.1, 4.3, 3.5, 2.2, 6, 1.9, 12, 16.6, 12.4, 28.3, 14.2],
  [29, 34.6, 48.4, 8.9, 22.3, 9.7, 26.1, 14.2, 10.6, 7.5, 29.1, 6.4, 22, 6.7, 17, 9.9, 12, 46.7, 51, 36.1, 39.7, 47, 26.4, 4.7, 4.2, 24.2, 19.5, 41.5, 38, 9.1, 7.2, 11.9, 11.9, 4, 4, 9.3, 13.2, 20.6, 19.9, 29.4, 29],
  [39.1, 47.7, 36.4, 5, 9.2, 5.5, 16.9, 9.6, 7.2, 31.9, 8.8, 6, 10.9, 23.5, 5.3, 17.6, 8, 4, 38.1, 53.3, 34.2, 43.9, 25.8, 5, 8.7, 21.3, 9, 32.7, 23.1, 34.8, 20.5, 13.3, 11, 20.4, 14.1, 3, 8.6, 20.9, 20.6, 12.6, 39.1],
  [29.9, 38.9, 36.6, 3, 3.2, 3, 21, 16.3, 32.5, 10, 4, 12.1, 30.1, 14.1, 23.9, 6.5, 12.9, 16.4, 46.3, 25, 26.9, 14.9, 22.8, 24.8, 3, 18.3, 23, 6.4, 19.7, 2.4, 11.9, 9.8, 5.7, 16, 12.9, 22.7, 16.4, 31.4, 3, 29.9],
  [14.9, 18.7, 30.1, 29.1, 8.1, 16.7, 16.7, 29.3, 35.4, 5, 10.8, 23.6, 21.6, 30.6, 15.6, 11.8, 6.8, 35, 17.5, 14.4, 10.4, 34, 32.9, 12.1, 23.2, 21.5, 5.4, 3, 7.5, 6.8, 15, 3, 19.5, 28.4, 26.6, 6, 14.9],
  [6.9, 10.1, 20.1, 19.8, 3, 26.4, 27.6, 34.1, 24.9, 18.2, 20.8, 9.9, 15.8, 29.3, 36.1, 32, 9.2, 16.4, 8.7, 7.1, 38.8, 19.1, 31.1, 23, 10.8, 29.3, 9.3, 22.7, 18.2, 4, 25.5, 10.9, 20.1, 23.7, 11, 6.9],
  [13.1, 21, 17.8, 14.5, 32.6, 26.8, 27.4, 11.8, 10.5, 18.5, 3, 10.8, 22, 25.4, 24, 36.7, 35.7, 39.3, 20.3, 24, 6.8, 6.5, 30, 11.8, 24.6, 37.5, 28.2, 26.7, 43, 40.9, 20.1, 42.6, 16.3, 33.5, 26.7, 15.7, 16.1, 11.5, 24.6, 4, 19.2, 10.3, 13.1],
  [20.2, 28.9, 14.2, 20.5, 28.1, 18.2, 3, 10.1, 18.1, 3, 15.2, 28.1, 31.7, 30.3, 34.9, 27.7, 36.3, 32, 14.4, 11.7, 31.1, 12.8, 25.1, 26.6, 31.4, 36.4, 26.1, 39.6, 29.3, 42.8, 12.8, 36.3, 36.2, 11.7, 18.3, 32, 10.3, 20.4, 7.2, 20.2],
  [24.5, 22.3, 3, 14.4, 20.6, 13.1, 26.7, 5, 4, 14.7, 31.3, 20.8, 31.2, 27.3, 26.3, 20.3, 24.8, 11.9, 28.4, 39.2, 32.6, 28.3, 25, 22.5, 36.5, 37.5, 31.4, 30.8, 26.4, 10.8, 18.6, 36.4, 35.3, 15, 40.2, 43.3, 40.1, 29.3, 5.5, 16.8, 25.5, 12.5, 24.5],
  [24.9, 11.1, 14.4, 13.3, 41.3, 13.4, 5, 12.2, 39.9, 42.1, 18, 26.4, 20.7, 8.1, 31.6, 15.4, 39.6, 27.9, 32.5, 43.3, 29.8, 44.6, 31.3, 9.8, 25.4, 9.5, 13.3, 3.5, 35.5, 28, 39.7, 37.1, 30.8, 18.3, 7.2, 21.6, 14.5, 16.9, 24.9],
  [14.3, 22.2, 4, 8.4, 8.6, 24.6, 36.8, 23.3, 6, 5, 34.4, 38, 18.1, 19.2, 19.8, 13.7, 39.4, 17.1, 7, 27, 17.5, 29.4, 39.3, 31.2, 32.3, 44.5, 19.3, 26.4, 23.2, 2.3, 35.2, 42.1, 32.6, 31.2, 25.4, 22.4, 16.3, 17, 26.5, 30.5, 10, 14.2, 20.4, 14.3],
  [7.4, 17.7, 7.4, 3, 9.9, 28.4, 26.9, 26.3, 3, 4, 31.9, 42.6, 33.3, 17.9, 18.6, 22.5, 33.4, 23.7, 7.4, 14, 7.9, 24.3, 16.1, 16.7, 29.5, 41.3, 35.3, 39.3, 25.2, 27.1, 19.2, 3, 22.1, 42.3, 6.2, 29.3, 25, 30.4, 22.4, 20.8, 29.1, 39.4, 21.2, 31, 7.4],
  [11.1, 16.4, 7.9, 8.2, 18, 27.1, 18.2, 24.6, 7.9, 3, 26.7, 39.2, 41.3, 11.2, 10, 17, 13.5, 22, 17.8, 12.8, 12.4, 3.8, 15.6, 5.5, 3, 33.7, 45.5, 46.3, 41.5, 23.7, 12, 12.7, 4.2, 21.8, 30.4, 10.2, 24.5, 36.5, 42.9, 32.8, 26.5, 39.5, 46, 35.1, 24.4, 11.1],
  [29.3, 18.2, 17.3, 12.5, 26.1, 13.1, 6.1, 24.2, 16.6, 23.6, 27.8, 25.4, 3, 6, 8.4, 14.9, 20, 4, 16.3, 9.3, 4.3, 19.1, 3.6, 22.1, 46.6, 43.1, 23.8, 15.5, 2.7, 23.4, 23.2, 10.8, 10.5, 15.6, 33.3, 41.6, 27, 16.9, 44.1, 56.9, 23.1, 15.9, 29.3],
  [33.2, 17.6, 34.4, 29.3, 36.8, 5.9, 3, 26.3, 19.3, 13.5, 5, 11.7, 14.8, 9, 19.3, 23.8, 6, 16.2, 18.2, 6.1, 7.6, 25, 30, 10.6, 17.9, 10.7, 36.8, 40.2, 22, 3.2, 3, 7.9, 27, 31.3, 21.7, 6.6, 39.9, 44.1, 30.9, 22.3, 17.5, 33.2],
  [26.6, 17.7, 38, 28.7, 7.6, 8.1, 26.6, 20.7, 12.1, 3, 11.7, 3, 25.2, 35.1, 13.3, 17.4, 14.2, 8.5, 19.7, 3, 12.9, 39.8, 20.3, 21.2, 15.6, 28.1, 23.9, 37.6, 40.4, 30.5, 3, 3, 30.1, 18.9, 20.1, 30.3, 29.7, 25.5, 18.3, 26.6],
  [17.5, 26.3, 22.5, 14.4, 12, 7.7, 26.5, 23.7, 7, 16.9, 16.8, 6, 29.5, 45.3, 14.4, 9.8, 14.8, 5.3, 6.7, 12.2, 33.1, 26.2, 18.7, 43.3, 28.6, 30.5, 38.3, 42.2, 7.5, 11.5, 37.9, 35, 21.7, 16.2, 42.8, 40.8, 18.8, 27.2, 17.5],
  [19.1, 37.5, 3, 10.7, 16, 6.7, 38.7, 8.1, 5, 20.5, 22.3, 22.2, 12, 36.3, 18.1, 13.4, 3.8, 7.4, 17.4, 12.5, 6.1, 6.2, 18.8, 42.1, 33.9, 14.8, 45.6, 25.4, 16.1, 44.4, 9.2, 22.8, 50.7, 28.8, 20, 16.6, 46.3, 44.7, 41, 21.7, 32.4, 19.1],
  [3, 37.9, 3, 5.1, 23.2, 22.4, 13.8, 35.8, 6.9, 4.1, 18.2, 23.4, 27.3, 24.7, 23.8, 29.6, 14.9, 4, 4, 30.7, 15.9, 6.2, 4.4, 15.7, 10.1, 33.7, 32.2, 16.5, 38.6, 24.7, 19.2, 30.7, 7.3, 41.4, 21.9, 23.8, 18.2, 33.3, 29.9, 37.4, 19.7, 33, 3],
  [20.4, 32.3, 11.4, 28.1, 28.4, 13.8, 25.5, 20.6, 33.5, 20.3, 17.6, 23.5, 22.9, 36.9, 37.7, 18.3, 30.5, 21, 9.2, 27.8, 20.2, 9.6, 3, 4.3, 12.8, 27.1, 16, 23.5, 35.4, 32.7, 12.9, 12, 29.9, 31.7, 20.5, 16.3, 8.5, 36, 20.4],
  [10.8, 28.3, 26.4, 47.5, 22.7, 3, 33, 12.8, 38.4, 30.8, 22, 42.5, 38.6, 13.6, 31.9, 33.4, 24.7, 21.6, 14.4, 25.1, 14.9, 34.3, 3, 17.5, 9, 32.3, 49.5, 36.1, 10.4, 17.2, 16.3, 38.9, 37.4, 22.3, 13.5, 16.8, 9, 38.8, 41.5, 20.5, 10.8],
];

const BAR_COUNT = FLOW_BARS.length;
const FRAME_MS = 180;
const IDLE_H = 4;

let timers = [];
let intervals = [];
let waveFrame = 0;
let barNodes = [];

function clearAll() {
  timers.forEach(clearTimeout);
  intervals.forEach(clearInterval);
  timers = [];
  intervals = [];
}
function later(ms, fn) {
  const id = setTimeout(fn, ms);
  timers.push(id);
}
function every(ms, fn) {
  const id = setInterval(fn, ms);
  intervals.push(id);
}
function fmtMs(ms) {
  if (ms < 1000) return `${ms} ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}
function randBetween(a, b) {
  return Math.round(a + Math.random() * (b - a));
}

function buildWave() {
  if (!el.wave) return;
  el.wave.innerHTML = "";
  barNodes = [];
  const frag = document.createDocumentFragment();
  for (let i = 0; i < BAR_COUNT; i++) {
    const b = document.createElement("div");
    b.className = "vd-bar";
    b.style.height = `${IDLE_H}px`;
    frag.appendChild(b);
    barNodes.push(b);
  }
  el.wave.appendChild(frag);
}

function setWave(state) {
  if (!el.waveWrap) return;
  el.waveWrap.classList.remove("is-listening", "is-idle", "is-polish");
  el.waveWrap.classList.add(state);
  if (state === "is-idle") {
    barNodes.forEach((bar) => {
      bar.style.height = `${IDLE_H}px`;
    });
  }
}

function applyFrame(frame) {
  for (let i = 0; i < BAR_COUNT; i++) {
    const seq = FLOW_BARS[i];
    const h = seq[frame % seq.length];
    barNodes[i].style.height = `${Math.max(2, h)}px`;
  }
}

function startWaveAnim() {
  stopWaveAnim();
  if (reduced) {
    barNodes.forEach((bar, i) => {
      bar.style.height = `${8 + (i % 5) * 4}px`;
    });
    return;
  }
  waveFrame = 0;
  applyFrame(0);
  every(FRAME_MS, () => {
    waveFrame += 1;
    applyFrame(waveFrame);
  });
}

function stopWaveAnim() {
  intervals.forEach(clearInterval);
  intervals = [];
}

function typeWords(node, text, { speed = 40, onDone } = {}) {
  node.innerHTML = "";
  const words = text.split(/(\s+)/).filter(Boolean);
  const cursor = document.createElement("span");
  cursor.className = "cursor";
  node.appendChild(cursor);
  let i = 0;
  function step() {
    if (i >= words.length) {
      cursor.remove();
      onDone && onDone();
      return;
    }
    const span = document.createElement("span");
    span.className = "tok";
    const w = words[i++];
    if (RACE.fillers.some((f) => w.toLowerCase().includes(f))) {
      span.classList.add("filler");
    }
    span.textContent = w;
    node.insertBefore(span, cursor);
    later(speed + Math.random() * 12, step);
  }
  step();
}

function typeChars(node, text, { speed = 14, onDone } = {}) {
  node.innerHTML = "";
  const cursor = document.createElement("span");
  cursor.className = "cursor";
  node.appendChild(cursor);
  let i = 0;
  function step() {
    if (i >= text.length) {
      cursor.remove();
      onDone && onDone();
      return;
    }
    const n = 1 + Math.floor(Math.random() * 2);
    const chunk = text.slice(i, i + n);
    i += chunk.length;
    const span = document.createElement("span");
    span.className = "tok";
    span.textContent = chunk;
    node.insertBefore(span, cursor);
    later(speed + Math.random() * 10, step);
  }
  step();
}

function markFixes(node, text) {
  let html = text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  for (const w of ["yesterday’s", "Send"]) {
    html = html.replace(
      new RegExp(`(${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "g"),
      '<span class="tok fix">$1</span>'
    );
  }
  node.innerHTML = html;
}

function setLocal(status, cls) {
  if (el.localStatus) {
    el.localStatus.textContent = status;
    el.localStatus.className = "lane-status" + (cls ? ` ${cls}` : "");
  }
}
function setFlow(status, cls) {
  if (el.cloudStatus) {
    el.cloudStatus.textContent = status;
    el.cloudStatus.className = "lane-status" + (cls ? ` ${cls}` : "");
  }
}

function runRace() {
  if (!el.root) return;
  clearAll();

  const localMs = reduced ? 380 : randBetween(280, RACE.localTargetMs);
  const flowMs = reduced ? 2200 : randBetween(RACE.flowMinMs, RACE.flowMaxMs);

  el.localText.textContent = "";
  el.cloudText.textContent = "";
  el.localBadge.textContent = "—";
  el.cloudBadge.textContent = "—";
  el.localBadge.className = "lane-badge";
  el.cloudBadge.className = "lane-badge wait";
  el.localLane?.classList.remove("won", "done");
  el.cloudLane?.classList.remove("won", "done", "lagging");
  el.cloudLane?.classList.add("lagging");
  if (el.caption) el.caption.textContent = "Local done. Cloud still waiting.";
  if (el.waveLabel) el.waveLabel.textContent = "Listening…";

  setLocal("Listening…", "live");
  setFlow("Listening…", "live");
  setWave("is-listening");
  startWaveAnim();

  const listenMs = reduced ? 120 : 900;

  later(listenMs, () => {
    setWave("is-polish");
    if (el.waveLabel) el.waveLabel.textContent = "Go";

    setLocal("On-device…", "live");
    typeWords(el.localText, RACE.raw, {
      speed: reduced ? 6 : 22,
      onDone: () => {
        later(reduced ? 40 : 120, () => {
          setLocal("Polish…", "live");
          el.localText.querySelectorAll(".filler").forEach((n) => {
            n.style.opacity = "0.4";
          });
          later(reduced ? 40 : 100, () => {
            typeChars(el.localText, RACE.clean, {
              speed: reduced ? 3 : 8,
              onDone: () => {
                markFixes(el.localText, RACE.clean);
                setLocal("Done", "done");
                el.localBadge.textContent = fmtMs(localMs);
                el.localBadge.className = "lane-badge win";
                el.localLane?.classList.add("won", "done");
                if (el.caption) {
                  el.caption.textContent = `Done ${fmtMs(localMs)}. Cloud still waiting…`;
                }
                stopWaveAnim();
                setWave("is-idle");
                if (el.waveLabel) el.waveLabel.textContent = "Local done";
              },
            });
          });
        });
      },
    });

    setFlow("Uploading…", "wait");
    el.cloudText.innerHTML =
      '<span class="pending"><span class="dot"></span><span class="dot"></span><span class="dot"></span> waiting</span>';

    const t1 = Math.round(flowMs * 0.28);
    const t2 = Math.round(flowMs * 0.55);
    const t3 = Math.round(flowMs * 0.78);

    later(t1, () => setFlow("Cloud…", "wait"));
    later(t2, () => setFlow("Waiting…", "wait"));
    later(t3, () => setFlow("Downloading…", "wait"));

    later(flowMs, () => {
      setFlow("Typing…", "live");
      el.cloudText.textContent = "";
      typeChars(el.cloudText, RACE.clean, {
        speed: reduced ? 8 : 16,
        onDone: () => {
          el.cloudText.textContent = RACE.clean;
          setFlow("Done", "done");
          el.cloudBadge.textContent = fmtMs(flowMs);
          el.cloudBadge.className = "lane-badge lose";
          el.cloudLane?.classList.remove("lagging");
          el.cloudLane?.classList.add("done");
          if (el.caption) {
            el.caption.textContent = `${fmtMs(localMs)} vs ${fmtMs(flowMs)} · ~${Math.round(flowMs / localMs)}x slower`;
          }
          if (el.waveLabel) el.waveLabel.textContent = "Done";
          later(reduced ? 1400 : 3200, runRace);
        },
      });
    });
  });
}

function initRace() {
  if (!el.wave) return;
  buildWave();
  setWave("is-idle");
  el.replay?.addEventListener("click", () => {
    clearAll();
    runRace();
  });
  if ("IntersectionObserver" in window) {
    let started = false;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting) && !started) {
          started = true;
          later(200, runRace);
          io.disconnect();
        }
      },
      { threshold: 0.2 }
    );
    io.observe(el.root);
  } else {
    later(500, runRace);
  }
}

/* ------------------------------------------------------------------ */
/* Speed flex — 80 vs 150                                              */
/* ------------------------------------------------------------------ */

const SPEED_LINE =
  "ship the project. how would you like the deck tomorrow morning?";

function runSpeedFlex() {
  const typed = document.getElementById("speed-typed");
  const spoken = document.getElementById("speed-spoken");
  const keys = document.getElementById("speed-keys");
  const mouth = document.getElementById("speed-mouth");
  if (!typed || !spoken) return;

  let keyIv = null;
  let mouthIv = null;
  let cycleT = null;

  function stopIvs() {
    if (keyIv) clearInterval(keyIv);
    if (mouthIv) clearInterval(mouthIv);
    if (cycleT) clearTimeout(cycleT);
    keyIv = mouthIv = cycleT = null;
  }

  function cycle() {
    stopIvs();
    typed.textContent = "";
    spoken.textContent = "";
    keys?.classList.remove("done");
    mouth?.classList.remove("done");

    if (reduced) {
      typed.textContent = SPEED_LINE.slice(0, 28) + "…";
      spoken.textContent = SPEED_LINE;
      mouth?.classList.add("done");
      return;
    }

    const mouthMsPerChar = 28;
    const keysMsPerChar = 55;
    let mi = 0;
    let ki = 0;

    const mouthCursor = document.createElement("span");
    mouthCursor.className = "cursor";
    spoken.appendChild(mouthCursor);

    keyIv = setInterval(() => {
      if (ki >= SPEED_LINE.length) {
        clearInterval(keyIv);
        keyIv = null;
        keys?.classList.add("done");
        return;
      }
      const n = 1 + (Math.random() > 0.7 ? 1 : 0);
      typed.textContent = SPEED_LINE.slice(0, Math.min(SPEED_LINE.length, ki + n));
      ki = typed.textContent.length;
    }, keysMsPerChar);

    mouthIv = setInterval(() => {
      if (mi >= SPEED_LINE.length) {
        clearInterval(mouthIv);
        mouthIv = null;
        mouthCursor.remove();
        spoken.textContent = SPEED_LINE;
        mouth?.classList.add("done");
        cycleT = setTimeout(() => {
          if (keyIv) {
            clearInterval(keyIv);
            keyIv = null;
          }
          cycleT = setTimeout(cycle, 2200);
        }, 900);
        return;
      }
      const n = 2 + Math.floor(Math.random() * 3);
      const next = SPEED_LINE.slice(0, Math.min(SPEED_LINE.length, mi + n));
      mi = next.length;
      spoken.textContent = next;
      spoken.appendChild(mouthCursor);
    }, mouthMsPerChar);
  }

  const section = document.getElementById("demo");
  if (!section || !("IntersectionObserver" in window)) {
    setTimeout(cycle, 600);
    return;
  }
  let started = false;
  const io = new IntersectionObserver(
    (entries) => {
      if (entries.some((e) => e.isIntersecting) && !started) {
        started = true;
        cycle();
        io.disconnect();
      }
    },
    { threshold: 0.25 }
  );
  io.observe(section);
}

/* Boot after deferred scripts parse */
function boot() {
  initBackground();
  initMotion();
  initRace();
  runSpeedFlex();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}
