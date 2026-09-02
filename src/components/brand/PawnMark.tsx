import Image from "next/image";

/**
 * The pink pawn — approved artwork, `public/brand/pawn-pink.webp`.
 *
 * Positioning is anchored on the piece itself, not on the file: the asset's
 * solid body occupies a known window inside a canvas that is mostly spatter,
 * so `register.css` offsets the image so that body lands exactly where the
 * reference puts it, cropped by the screen edge the same way. The spatter
 * then falls where the artwork draws it.
 */
export function PawnMark({ className }: { className?: string }) {
  return (
    <Image
      src="/brand/pawn-pink.webp"
      alt=""
      aria-hidden="true"
      width={640}
      height={665}
      className={className}
      priority
    />
  );
}
