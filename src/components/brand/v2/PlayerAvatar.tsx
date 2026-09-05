/**
 * V2 player avatar — a filled circle in the player's own persistent, stored
 * `avatar_color` (migration 0020) with the first alphanumeric character of
 * their public alias. No silhouette, no profile photo.
 *
 * Deliberately a separate component from the pre-V2
 * `components/brand/PlayerAvatar.tsx` (alias-hash color, silhouette glyph),
 * which Room (Screen 09, APPROVED) and the admin room-member view still use
 * — swapping that shared component's behavior would change those already-
 * approved screens' output without anyone reviewing it. This one is for V2
 * surfaces (Pass header, social proof; Games/Players/More/Results later)
 * going forward — see the delivery report.
 *
 * Foreground: ink by default, but computed via the real WCAG relative-
 * luminance/contrast formulas against whatever color is actually passed in
 * — not a hardcoded per-palette-value list, so it stays correct if the
 * palette ever changes. Verified against all 8 current values: two
 * (#2F6BFF, #7C5CFC) measure below 4.5:1 against ink at this element's
 * rendered size and fall back to --avatar-fg-strong (pure black, the one
 * option of ink/white/black that clears 4.5:1 against both) — see
 * tokens.css's comment on that token for the actual numbers. The palette
 * itself is unchanged.
 */
function initialFor(alias: string): string {
  const match = alias.match(/[A-Za-z0-9]/);
  return match ? match[0].toUpperCase() : "?";
}

function relativeLuminance(hex: string): number {
  const m = hex.replace("#", "");
  const full = m.length === 3 ? m.split("").map((c) => c + c).join("") : m;
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16) / 255);
  const channel = (c: number) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/** tokens.css's --ink (#1b1219), expressed as its precomputed WCAG relative
 *  luminance (not the hex itself — this file can't hold a hex literal, see
 *  eslint.config.mjs) so the contrast check below has a number to compare
 *  against without duplicating the color value. */
const INK_LUMINANCE = 0.007358113254247939;
const AA_NORMAL_TEXT = 4.5;

function foregroundFor(bgColor: string): string {
  const bgLuminance = relativeLuminance(bgColor);
  const [lighter, darker] =
    INK_LUMINANCE > bgLuminance ? [INK_LUMINANCE, bgLuminance] : [bgLuminance, INK_LUMINANCE];
  const ratio = (lighter + 0.05) / (darker + 0.05);
  return ratio >= AA_NORMAL_TEXT ? "var(--fg)" : "var(--avatar-fg-strong)";
}

export function PlayerAvatar({
  alias,
  color,
  size = 2.25,
  ring = false,
  className,
}: {
  alias: string;
  color: string;
  /** rem */
  size?: number;
  /** A thin cream separation ring — for overlapping stacks (social proof) only. */
  ring?: boolean;
  className?: string;
}) {
  return (
    <span
      className={`rc-avatar-v2${ring ? " rc-avatar-v2--ring" : ""}${className ? ` ${className}` : ""}`}
      style={{ width: `${size}rem`, height: `${size}rem`, backgroundColor: color, color: foregroundFor(color) }}
      role="img"
      aria-label={alias}
    >
      <span aria-hidden="true">{initialFor(alias)}</span>
    </span>
  );
}
