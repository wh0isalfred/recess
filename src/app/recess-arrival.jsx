import { useEffect, useRef, useState } from "react";

/* ------------------------------------------------------------------ *
 * RECESS — Phase 3, screen pass 01
 * 01 Splash / entrance state  •  02 Landing hero
 *
 * One arrival experience at "/". The splash is not a route and not a
 * loading screen: mark, eyebrow, wordmark, brush and die are laid out
 * in their LANDING positions, and the splash is a transform offset on
 * those same nodes. Releasing the transform opens the poster into the
 * product — the die travels from lower-left to upper-right, the mark
 * from centre to the top-left corner, the masthead lifts and settles.
 *
 * PORTING NOTES (Next.js / Tailwind v4)
 *  - Add "use client".
 *  - Swap INTRO_SEEN for sessionStorage (see below); gate the initial
 *    phase behind a mounted check to avoid hydration mismatch.
 *  - Hex values are literal so this runs standalone — replace with the
 *    Phase 2 tokens from src/styles/tokens.css.
 * ------------------------------------------------------------------ */

// Session-level replay guard.
// In the app:  sessionStorage.getItem("recess.intro") === "1"
let INTRO_SEEN = false;

const SPLASH_MS = 1150;

const CSS = `
@import url('https://fonts.googleapis.com/css2?family=Archivo+Black&family=Archivo:wght@400;500;600;700&display=swap');

.recess-root {
  --paper:      #F4EDE2;
  --paper-deep: #EBE1D1;
  --ink:        #1F1522;
  --pink:       #E52A5E;
  --pink-hot:   #F0426B;
  --pink-deep:  #B81B41;

  --e: cubic-bezier(.16,1,.3,1);
  --e-stamp: cubic-bezier(.2,1.15,.3,1);

  position: relative;
  isolation: isolate;
  overflow: hidden;
  background: var(--paper);
  color: var(--ink);
  font-family: Archivo, "Helvetica Neue", Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
}

.recess-root::before {
  content: "";
  position: absolute; inset: 0; z-index: 0; pointer-events: none;
  background:
    radial-gradient(110% 70% at 50% 0%, rgba(255,255,255,.6), transparent 62%),
    linear-gradient(180deg, var(--paper) 0%, var(--paper-deep) 100%);
}
.grain {
  position: absolute; inset: -20%; z-index: 6; pointer-events: none;
  opacity: .26; mix-blend-mode: multiply;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='200' height='200'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='200' height='200' filter='url(%23n)' opacity='.5'/%3E%3C/svg%3E");
}

.stage { position: relative; }

.page {
  position: relative; z-index: 2;
  display: flex; flex-direction: column; align-items: center;
  min-height: 100dvh;
  padding: 18px 18px 20px;
  text-align: center;
}

.sr-only {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0;
}

/* top bar --------------------------------------------------------- */
.topbar {
  width: 100%; display: flex; align-items: flex-start;
  justify-content: space-between; min-height: 26px;
}
.mark {
  display: block; width: 26px; color: var(--ink);
  transform-origin: 50% 50%;
  transition: transform .9s var(--e);
}
.mark svg { display: block; width: 100%; height: auto; }
.next {
  font-size: 12px; font-weight: 700; letter-spacing: .07em;
  text-transform: uppercase; text-decoration: none; color: var(--pink);
  padding-top: 2px;
}
.next:hover { color: var(--pink-deep); }
.next:focus-visible { outline: 2px solid var(--pink); outline-offset: 4px; }

/* masthead — mark aside, this block moves as one -------------------- */
.mast {
  width: 100%; margin-top: 6vh;
  transform-origin: 50% 45%;
  transition: transform .9s var(--e);
  will-change: transform;
}
.eyebrow {
  margin: 0 0 8px;
  font-size: 15px; font-weight: 700; letter-spacing: .05em;
}
.eyebrow-in { display: inline-block; }
.eyebrow em { font-style: normal; color: var(--pink); }

.word { margin: 0; }
.word-in { display: block; }
.word svg { display: block; width: 100%; height: auto; overflow: visible; }
.word text {
  font-family: "Archivo Black", "Arial Black", Impact, sans-serif;
  font-weight: 900;
}

.brush { margin-top: -4%; }
.brush-in { display: block; }
.brush svg { display: block; width: 82%; margin: 0 auto; height: auto; }

/* die -------------------------------------------------------------- */
.die {
  position: absolute; z-index: 4;
  top: 6.5vh; right: 1vw; width: 25vw;
  transform-origin: 50% 50%;
  transform: rotate(7deg);
  transition: transform 1s var(--e);
  will-change: transform;
}
.die-in { display: block; }
.die svg { display: block; width: 100%; height: auto; overflow: visible; }

/* hero body -------------------------------------------------------- */
.body { width: 100%; padding-top: 4.5vh; }
.lede {
  margin: 0 auto 22px; max-width: 25ch;
  font-size: 15.5px; line-height: 1.55; font-weight: 500;
}
.lede em { font-style: normal; color: var(--pink); }

.meta {
  display: flex; align-items: stretch; justify-content: center;
  gap: 26px; margin-bottom: 26px;
}
.meta-col { text-align: left; }
.meta-col + .meta-col { padding-left: 26px; border-left: 1.5px solid rgba(31,21,34,.22); }
.meta-lab { display: block; font-size: 13px; font-weight: 700; letter-spacing: .04em; }
.meta-num {
  display: block; margin: 1px 0 2px;
  font-family: "Archivo Black", "Arial Black", sans-serif;
  font-size: 34px; line-height: .95; letter-spacing: -.02em;
}
.meta-sub { display: block; font-size: 12px; font-weight: 700; letter-spacing: .06em; opacity: .72; }

.cta {
  display: flex; align-items: center; justify-content: center; gap: 12px;
  width: 100%; padding: 17px 24px; border-radius: 13px;
  background: var(--pink); color: #FFF6F0;
  font-size: 17px; font-weight: 700; letter-spacing: .09em;
  text-decoration: none;
  box-shadow: 0 3px 0 var(--pink-deep);
  transition: transform .15s ease, box-shadow .15s ease, background .15s ease;
}
.cta:hover { background: var(--pink-hot); }
.cta:active { transform: translateY(3px); box-shadow: 0 0 0 var(--pink-deep); }
.cta:focus-visible { outline: 3px solid var(--ink); outline-offset: 3px; }

.note { margin: 14px 0 0; font-size: 12.5px; font-weight: 500; opacity: .72; }

.hint { margin-top: auto; padding-top: 18px; color: rgba(31,21,34,.45); }
.hint svg { display: block; width: 18px; height: auto; }

/* ---- SPLASH STATE ------------------------------------------------ */
.stage[data-phase="splash"] .mark {
  transform: translate(calc(50vw - 18px - 50%), 8vh) scale(1.9);
}
.stage[data-phase="splash"] .mast { transform: translateY(8vh) scale(1.07); }
.stage[data-phase="splash"] .die  { transform: translate(-58vw, 62vh) scale(3.1) rotate(-9deg); }
.stage[data-phase="splash"] .reveal { opacity: 0; transform: translateY(14px); }

.reveal { opacity: 1; transform: none; transition: opacity .5s ease .18s, transform .6s var(--e) .18s; }

/* ---- INTRO CHOREOGRAPHY (first arrival only) --------------------- */
.stage.intro .mark-in    { animation: rc-pop .4s var(--e) both; }
.stage.intro .eyebrow-in { animation: rc-wipe .48s var(--e) .14s both; }
.stage.intro .word-in    { animation: rc-stamp .46s var(--e-stamp) .26s both; }
.stage.intro .brush-in   { animation: rc-sweep .5s var(--e) .46s both; }
.stage.intro .die-in     { animation: rc-drop .6s var(--e) .36s both; }

@keyframes rc-pop   { from { opacity: 0; transform: translateY(-8px); } }
@keyframes rc-wipe  { from { opacity: 0; clip-path: inset(0 100% 0 0); }
                      to   { opacity: 1; clip-path: inset(0 -2% 0 0); } }
@keyframes rc-stamp { from { opacity: 0; transform: scale(1.07); filter: blur(3px); }
                      to   { opacity: 1; transform: scale(1); filter: blur(0); } }
@keyframes rc-sweep { from { clip-path: inset(0 100% 0 0); }
                      to   { clip-path: inset(0 -10% 0 0); } }
@keyframes rc-drop  { from { opacity: 0; transform: translate(-8%, 14%) rotate(-16deg); }
                      to   { opacity: 1; transform: none; } }

/* ---- DESKTOP ------------------------------------------------------ */
@media (min-width: 820px) {
  .page { max-width: 700px; margin: 0 auto; padding: 34px 24px 30px; }
  .mark { width: 34px; }
  .next { font-size: 13px; }
  .mast { margin-top: 9vh; }
  .eyebrow { font-size: 19px; margin-bottom: 12px; }
  .brush svg { width: 76%; }
  .die {
    top: 8vh; right: auto; left: 50%; margin-left: 200px; width: 150px;
  }
  .body { padding-top: 5vh; }
  .lede { font-size: 19px; max-width: 30ch; margin-bottom: 30px; }
  .meta { gap: 34px; margin-bottom: 32px; }
  .meta-col + .meta-col { padding-left: 34px; }
  .meta-num { font-size: 44px; }
  .meta-lab { font-size: 15px; }
  .cta { width: auto; min-width: 340px; margin: 0 auto; padding: 19px 40px; font-size: 18px; }
  .note { font-size: 14px; }
  .stage[data-phase="splash"] .mark { transform: translate(calc(50vw - 24px - 50%), 9vh) scale(2.1); }
  .stage[data-phase="splash"] .mast { transform: translateY(9vh) scale(1.05); }
  .stage[data-phase="splash"] .die  { transform: translate(-40vw, 50vh) scale(3.4) rotate(-9deg); }
}

/* ---- REDUCED MOTION ----------------------------------------------- */
@media (prefers-reduced-motion: reduce) {
  .recess-root *, .recess-root *::before, .recess-root *::after {
    animation: none !important;
    transition-duration: 1ms !important;
  }
}

/* preview-only control — delete when porting */
.replay {
  position: absolute; z-index: 7; right: 10px; bottom: 8px;
  background: none; border: 0; cursor: pointer;
  font: inherit; font-size: 10px; letter-spacing: .12em;
  color: rgba(31,21,34,.3);
}
.replay:hover { color: var(--pink); }
`;

/* ---------- artwork ------------------------------------------------ */

/* three small figures with rays — the RECESS play mark */
function PlayMark() {
  return (
    <svg viewBox="0 0 72 52" aria-hidden="true"
      fill="none" stroke="currentColor" strokeWidth="2.6"
      strokeLinecap="round" strokeLinejoin="round">
      {/* rays over the centre figure */}
      <path d="M36 3v5M25 6l2.5 4.5M47 6l-2.5 4.5M17 13l4 2.8M55 13l-4 2.8" />
      {/* centre figure */}
      <circle cx="36" cy="20" r="4.6" fill="currentColor" stroke="none" />
      <path d="M36 25.5v9M27.5 29.5 36 27l8.5 2.5M36 34.5l-5 8M36 34.5l5 8" />
      {/* left figure */}
      <circle cx="14" cy="25" r="4" fill="currentColor" stroke="none" />
      <path d="M14 29.5v8M6.5 33 14 31l7.5 2M14 37.5l-4.5 7M14 37.5l4.5 7" />
      {/* right figure */}
      <circle cx="58" cy="25" r="4" fill="currentColor" stroke="none" />
      <path d="M58 29.5v8M50.5 33 58 31l7.5 2M58 37.5l-4.5 7M58 37.5l4.5 7" />
    </svg>
  );
}

/* per-letter poster wordmark: forced advance widths keep the block
   exactly 1000 units wide whether or not Archivo Black has loaded */
const LETTERS = [
  { c: "R", x: 4,   w: 174, s: 252, y: 200, r: -2.6 },
  { c: "E", x: 180, w: 150, s: 244, y: 195, r: -1.2 },
  { c: "C", x: 332, w: 170, s: 250, y: 199, r: 0.6 },
  { c: "E", x: 504, w: 150, s: 243, y: 196, r: 1.4 },
  { c: "S", x: 656, w: 166, s: 248, y: 201, r: 2.4 },
  { c: "S", x: 824, w: 168, s: 254, y: 197, r: 3.4 },
];

function Wordmark() {
  const glyphs = (fill) =>
    LETTERS.map((l, i) => (
      <text
        key={i}
        x={l.x} y={l.y} fontSize={l.s}
        textLength={l.w} lengthAdjust="spacingAndGlyphs"
        fill={fill}
        transform={`rotate(${l.r} ${l.x + l.w / 2} ${l.y})`}
      >
        {l.c}
      </text>
    ));

  return (
    <svg viewBox="0 0 1000 224" aria-hidden="true">
      <defs>
        <filter id="rc-rough" x="-4%" y="-14%" width="108%" height="130%">
          <feTurbulence type="fractalNoise" baseFrequency="0.014 0.045" numOctaves="3" seed="9" result="n" />
          <feDisplacementMap in="SourceGraphic" in2="n" scale="7" xChannelSelector="R" yChannelSelector="G" />
        </filter>

        {/* sparse ink breakup */}
        <filter id="rc-speck" filterUnits="userSpaceOnUse" x="0" y="0" width="1000" height="224">
          <feTurbulence type="fractalNoise" baseFrequency="0.075" numOctaves="3" seed="5" result="t" />
          <feColorMatrix in="t" type="luminanceToAlpha" result="a" />
          <feComponentTransfer in="a" result="b">
            <feFuncA type="linear" slope="3.2" intercept="-1.72" />
          </feComponentTransfer>
          <feFlood floodColor="#000" result="k" />
          <feComposite in="k" in2="b" operator="in" />
        </filter>

        <mask id="rc-distress" maskUnits="userSpaceOnUse" x="0" y="0" width="1000" height="224">
          <rect x="0" y="0" width="1000" height="224" fill="#fff" />
          <rect x="0" y="0" width="1000" height="224" filter="url(#rc-speck)" />
        </mask>
      </defs>

      <g filter="url(#rc-rough)">
        {/* pink off-register ghost */}
        <g transform="translate(-9,11)" opacity="0.85">{glyphs("#E52A5E")}</g>
        <g mask="url(#rc-distress)">{glyphs("#1F1522")}</g>
      </g>
    </svg>
  );
}

function Brush() {
  return (
    <svg viewBox="0 0 1000 120" aria-hidden="true">
      <defs>
        <filter id="rc-bristle" x="-4%" y="-30%" width="108%" height="170%">
          <feTurbulence type="fractalNoise" baseFrequency="0.014 0.085" numOctaves="3" seed="4" result="n" />
          <feDisplacementMap in="SourceGraphic" in2="n" scale="14" xChannelSelector="R" yChannelSelector="G" />
        </filter>
      </defs>
      <g filter="url(#rc-bristle)" fill="#E52A5E">
        {/* main sweep — heavy at the left, tapering up to the right */}
        <path d="M64 96C190 52 400 30 640 26c110-2 210 2 296-6l-6 20c-92 14-196 12-300 16-232 8-430 30-556 62z" />
        {/* second lighter stroke under the left half */}
        <path d="M150 108c150-30 330-44 520-50l-4 13c-186 10-360 26-508 52z" opacity=".8" />
        {/* flick + spatter */}
        <path d="M912 20c22-3 44-8 66-16l-4 15c-20 6-41 9-62 11z" opacity=".9" />
        <circle cx="988" cy="8" r="6" opacity=".85" />
        <circle cx="46" cy="106" r="5" opacity=".7" />
        <circle cx="24" cy="92" r="3.4" opacity=".55" />
      </g>
    </svg>
  );
}

function Die() {
  const pips = (matrix, pts) => (
    <g transform={matrix} fill="#150F1A">
      {pts.map(([x, y], i) => <circle key={i} cx={x} cy={y} r="0.088" />)}
    </g>
  );

  return (
    <svg viewBox="-26 -22 252 274" aria-hidden="true">
      <defs>
        <filter id="rc-die" x="-12%" y="-12%" width="124%" height="124%">
          <feTurbulence type="fractalNoise" baseFrequency="0.028" numOctaves="2" seed="13" result="n" />
          <feDisplacementMap in="SourceGraphic" in2="n" scale="3.5" xChannelSelector="R" yChannelSelector="G" />
        </filter>
        <filter id="rc-spray" x="-40%" y="-40%" width="180%" height="180%">
          <feTurbulence type="fractalNoise" baseFrequency="0.16" numOctaves="3" seed="21" result="t" />
          <feColorMatrix in="t" type="luminanceToAlpha" result="a" />
          <feComponentTransfer in="a" result="b">
            <feFuncA type="linear" slope="3.6" intercept="-1.95" />
          </feComponentTransfer>
          <feFlood floodColor="#1F1522" result="k" />
          <feComposite in="k" in2="b" operator="in" />
          <feComposite in2="SourceGraphic" operator="in" />
        </filter>
      </defs>

      {/* print spray around the lower-left of the object */}
      <ellipse cx="70" cy="180" rx="110" ry="86" fill="#1F1522" opacity=".55" filter="url(#rc-spray)" />

      <g filter="url(#rc-die)" stroke="#1F1522" strokeWidth="4" strokeLinejoin="round">
        <path d="M100 8 192 60 100 112 8 60Z" fill="#F0426B" />
        <path d="M8 60 100 112 100 216 8 164Z" fill="#D8244F" />
        <path d="M192 60 100 112 100 216 192 164Z" fill="#B81B41" />
      </g>

      <g>
        {/* top face: 6 */}
        {pips("matrix(92,-52,92,52,8,60)",
          [[0.3, 0.22], [0.7, 0.22], [0.3, 0.5], [0.7, 0.5], [0.3, 0.78], [0.7, 0.78]])}
        {/* left face: 3 */}
        {pips("matrix(92,52,0,104,8,60)", [[0.26, 0.24], [0.5, 0.5], [0.74, 0.76]])}
        {/* right face: 2 */}
        {pips("matrix(92,-52,0,104,100,112)", [[0.3, 0.3], [0.7, 0.7]])}
      </g>
    </svg>
  );
}

function Chevron() {
  return (
    <svg viewBox="0 0 24 14" aria-hidden="true" fill="none"
      stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 2l10 10L22 2" />
    </svg>
  );
}

/* ---------- component ---------------------------------------------- */

function initialPhase() {
  if (typeof window === "undefined") return "landing";
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  return INTRO_SEEN || reduced ? "landing" : "splash";
}

export default function RecessArrival() {
  const [phase, setPhase] = useState(initialPhase);
  const [runId, setRunId] = useState(0);
  const played = useRef(phase === "splash");
  const timer = useRef(null);

  useEffect(() => {
    INTRO_SEEN = true;
    if (phase !== "splash") return;
    timer.current = setTimeout(() => setPhase("landing"), SPLASH_MS);
    return () => clearTimeout(timer.current);
  }, [phase, runId]);

  // preview-only
  const replay = () => {
    clearTimeout(timer.current);
    played.current = true;
    setRunId((r) => r + 1);
    setPhase("splash");
  };

  return (
    <div className="recess-root">
      <style>{CSS}</style>

      <div key={runId} className={"stage" + (played.current ? " intro" : "")} data-phase={phase}>
        <div className="grain" aria-hidden="true" />

        <div className="die" aria-hidden="true">
          <span className="die-in"><Die /></span>
        </div>

        <div className="page">
          <header className="topbar">
            <span className="mark" aria-hidden="true">
              <span className="mark-in"><PlayMark /></span>
            </span>
            <a className="next reveal" href="#next-recess">
              Next RECESS <span aria-hidden="true">↗</span>
            </a>
          </header>

          <div className="mast">
            <p className="eyebrow">
              <span className="eyebrow-in">ALL WORK. <em>NO PLAY...</em></span>
            </p>
            <h1 className="word">
              <span className="sr-only">RECESS</span>
              <span className="word-in"><Wordmark /></span>
            </h1>
            <div className="brush" aria-hidden="true">
              <span className="brush-in"><Brush /></span>
            </div>
          </div>

          <div className="body reveal">
            <p className="lede">
              RECESS is our night to embrace that inner child and have <em>real fun.</em>
            </p>

            <div className="meta">
              <div className="meta-col">
                <span className="meta-lab">FRI</span>
                <span className="meta-num">11</span>
                <span className="meta-sub">SEPT 2026</span>
              </div>
              <div className="meta-col">
                <span className="meta-num">8:00</span>
                <span className="meta-lab">PM</span>
                <span className="meta-sub">WAT</span>
              </div>
            </div>

            <a
              className="cta"
              href="/register"
              onClick={(e) => e.preventDefault() /* PREVIEW ONLY — remove */}
            >
              I'M IN <span aria-hidden="true">→</span>
            </a>

            <p className="note">Come solo or bring your people.</p>
          </div>

          <div className="hint reveal" aria-hidden="true"><Chevron /></div>
        </div>

        <button className="replay" onClick={replay}>REPLAY INTRO</button>
      </div>
    </div>
  );
}
