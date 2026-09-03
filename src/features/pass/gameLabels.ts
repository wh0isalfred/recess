import type { GamePlatform } from "./types";

/**
 * `games.icon_url` exists in the schema but is null for every seeded game —
 * nothing to read yet. This is the smallest maintainable stand-in: a label
 * for the platform (already a real enum column) and a small original glyph
 * per known game slug, not a redesign of the Game Library to carry launch
 * metadata it doesn't have. When icon_url is populated for real, this
 * mapping is the one place that goes away.
 *
 * Icons are deliberately generic silhouettes, not the games' own marks —
 * Among Us, Skribbl and Kahoot are third-party products; RECESS draws its
 * own small glyph for each rather than reproducing their logos.
 */

export function platformLabel(platform: GamePlatform): string {
  switch (platform) {
    case "INSTALL":
      return "INSTALL APP";
    case "BROWSER":
      return "BROWSER";
    case "NATIVE":
      // Not shown in the supplied reference — no seeded game currently uses
      // it. "OPEN APP" is the sensible reading of NATIVE (already installed,
      // unlike INSTALL) until a real one exists to confirm the copy against.
      return "OPEN APP";
  }
}

const ICONS: Record<string, "crew" | "pencil" | "bolt"> = {
  "among-us": "crew",
  skribbl: "pencil",
  trivia: "bolt",
};

export function gameIconKind(slug: string): "crew" | "pencil" | "bolt" | "dot" {
  return ICONS[slug] ?? "dot";
}
