import Image from "next/image";

/**
 * Card-sized game artwork, with a graceful fallback when `artworkUrl` is
 * null — which it is for every real game right now (see the note in
 * migration 0018: no per-game artwork has been supplied yet, and this
 * component is not the place to fabricate it). The fallback is branded, not
 * a broken-image icon or empty space: the game's own first letter on the
 * accent fill, so a card reads correctly whether or not art exists yet.
 *
 * `artworkUrl` is constrained at the database level to a same-origin
 * relative path (see games_artwork_url_same_origin in the migration), so
 * this never has to defend against an arbitrary external URL reaching
 * next/image.
 */
export function GameArt({
  artworkUrl,
  name,
  size = 3,
  className,
}: {
  artworkUrl: string | null | undefined;
  name: string;
  size?: number;
  className?: string;
}) {
  const px = size * 16;

  if (artworkUrl) {
    return (
      <Image
        src={artworkUrl}
        alt=""
        aria-hidden="true"
        width={px}
        height={px}
        className={`rc-game-art ${className ?? ""}`}
      />
    );
  }

  return (
    <div
      className={`rc-game-art rc-game-art--fallback ${className ?? ""}`}
      style={{ width: `${size}rem`, height: `${size}rem` }}
      aria-hidden="true"
    >
      {name.charAt(0).toUpperCase()}
    </div>
  );
}
