/**
 * A colored circle with a human silhouette — the roster avatar for Screen 09
 * and the admin room-member views. No profile pictures, no avatar upload.
 *
 * Color is derived from the alias itself, not randomly assigned: the same
 * alias always lands on the same color for the whole event, with no
 * Math.random() and no server-side color storage to keep in sync. A small,
 * fixed, on-brand palette — not a full hue wheel — so colors stay legible on
 * the dark ground this renders on and never accidentally read as a status
 * signal (see the note below).
 *
 * Deliberately not meaningful: two players sharing a color is expected and
 * fine. Nothing about RECESS's state is ever communicated through avatar
 * color alone — the alias text and the YOU badge carry the actual meaning.
 */

const PALETTE = [
  "var(--pink-lift)",
  "var(--cobalt-lift)",
  "var(--amber)",
  "var(--go)",
  "var(--alert)",
  "var(--fg-soft)",
] as const;

function colorForAlias(alias: string): string {
  let hash = 0;
  for (let i = 0; i < alias.length; i++) {
    hash = (hash * 31 + alias.charCodeAt(i)) | 0;
  }
  return PALETTE[Math.abs(hash) % PALETTE.length];
}

export function PlayerAvatar({ alias, size = 2 }: { alias: string; size?: number }) {
  return (
    <svg
      viewBox="0 0 32 32"
      width={`${size}rem`}
      height={`${size}rem`}
      aria-hidden="true"
      className="rc-avatar"
    >
      <circle cx="16" cy="16" r="16" fill={colorForAlias(alias)} />
      <circle cx="16" cy="12.5" r="5.5" fill="rgba(0,0,0,0.35)" />
      <path d="M5 29c1.6-6.4 6.2-9.5 11-9.5s9.4 3.1 11 9.5Z" fill="rgba(0,0,0,0.35)" />
    </svg>
  );
}
