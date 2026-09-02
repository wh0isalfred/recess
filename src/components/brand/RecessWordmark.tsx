/**
 * The RECESS wordmark and the pink gesture that sits under it.
 *
 * Both are brand primitives — the wordmark signs the pass, the results screen
 * and anything else the brand puts its name on — so they live here rather
 * than inside the landing composition.
 *
 * The reference wordmark is painted lettering, not a typeface. What follows
 * gets as close as Archivo Black plus SVG filters reasonably can. The
 * references measure about 2.4 : 1 across the word against its cap height,
 * where Archivo Black sets at roughly 6 : 1, so each letter is given a forced
 * advance width and squeezed to about 43% — which lands the stem-to-letter
 * ratio near the reference's third. Baselines dip toward the ends and the
 * tilts fan outward, reproducing the shallow arch the word sits on. Then
 * displacement roughens the contour and a turbulence mask erodes specks out
 * of the ink.
 *
 * `textLength` locks the block to exactly 1000 units wide, so the wordmark
 * fills its container at any viewport and does not reflow when the display
 * face finishes loading.
 *
 * This is an approximation of painted letterforms, not a reproduction. A
 * supplied `public/brand/recess-wordmark.svg` would replace the <text> layers
 * below without changing anything else on the screen.
 */

type Glyph = {
  char: string;
  /** left edge, in viewBox units */
  x: number;
  /** forced advance width — the squeeze that condenses the face */
  w: number;
  size: number;
  baseline: number;
  /** degrees, part of the arch */
  tilt: number;
};

const GLYPHS: Glyph[] = [
  { char: "R", x: 0, w: 175, size: 562, baseline: 476, tilt: -5.5 },
  { char: "E", x: 175, w: 160, size: 552, baseline: 459, tilt: -3.3 },
  { char: "C", x: 335, w: 175, size: 558, baseline: 451, tilt: -1.1 },
  { char: "E", x: 510, w: 160, size: 550, baseline: 451, tilt: 1.1 },
  { char: "S", x: 670, w: 165, size: 556, baseline: 459, tilt: 3.3 },
  { char: "S", x: 835, w: 165, size: 566, baseline: 476, tilt: 5.5 },
];

export function RecessWordmark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 1000 500" className={className} aria-hidden="true">
      <defs>
        <filter id="rc-wordmark-rough" x="-4%" y="-10%" width="108%" height="124%">
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.010 0.026"
            numOctaves="3"
            seed="9"
            result="noise"
          />
          <feDisplacementMap
            in="SourceGraphic"
            in2="noise"
            scale="7"
            xChannelSelector="R"
            yChannelSelector="G"
          />
        </filter>

        {/* Sparse specks, used as holes in the mask, so the ink breaks up. */}
        <filter
          id="rc-wordmark-speck"
          filterUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1000"
          height="500"
        >
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.036"
            numOctaves="3"
            seed="5"
            result="noise"
          />
          <feColorMatrix
            in="noise"
            type="matrix"
            values="0 0 0 0 0
                    0 0 0 0 0
                    0 0 0 0 0
                    -14 0 0 0 4.7"
          />
        </filter>

        <mask
          id="rc-wordmark-distress"
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1000"
          height="500"
        >
          <rect x="0" y="0" width="1000" height="500" fill="white" />
          <rect x="0" y="0" width="1000" height="500" filter="url(#rc-wordmark-speck)" />
        </mask>
      </defs>

      <g filter="url(#rc-wordmark-rough)" mask="url(#rc-wordmark-distress)">
        {GLYPHS.map((g, i) => (
          <text
            key={`${g.char}-${i}`}
            x={g.x}
            y={g.baseline}
            fontSize={g.size}
            textLength={g.w}
            lengthAdjust="spacingAndGlyphs"
            fill="currentColor"
            transform={`rotate(${g.tilt} ${g.x + g.w / 2} ${g.baseline})`}
            style={{ fontFamily: "var(--font-display-family), system-ui, sans-serif" }}
          >
            {g.char}
          </text>
        ))}
      </g>
    </svg>
  );
}

/**
 * The pink gesture. A painted sweep, not a rule: loaded at the left, thinning
 * as it rises to the right and ending in a flick, with a lighter second pass
 * beneath and spatter where the brush left the paper. Filled paths, then
 * displaced so the edges break instead of staying vector-clean.
 *
 * Same caveat as the wordmark — a supplied `public/brand/brush-pink.svg`
 * would drop straight in.
 */
export function BrushGesture({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 1000 200" className={className} aria-hidden="true">
      <defs>
        <filter id="rc-brush-bristle" x="-4%" y="-24%" width="108%" height="152%">
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.011 0.06"
            numOctaves="3"
            seed="4"
            result="noise"
          />
          <feDisplacementMap
            in="SourceGraphic"
            in2="noise"
            scale="18"
            xChannelSelector="R"
            yChannelSelector="G"
          />
        </filter>
      </defs>

      <g filter="url(#rc-brush-bristle)" fill="var(--accent)">
        {/* the loaded sweep — heavy at the left, thinning into a flick */}
        <path d="M26 112c150-58 400-92 668-98 104-2 196 4 272-12l-12 52c-90 16-176 10-258 14-246 12-462 44-644 114z" />
        {/* lighter second pass beneath the left half */}
        <path d="M110 186c176-46 396-74 634-86l-6 26c-228 14-424 40-598 82z" opacity="0.5" />
        {/* spatter where the brush left the paper */}
        <circle cx="972" cy="26" r="9" opacity="0.8" />
        <circle cx="20" cy="150" r="8" opacity="0.55" />
        <circle cx="58" cy="180" r="4.5" opacity="0.4" />
      </g>
    </svg>
  );
}
