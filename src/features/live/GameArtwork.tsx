"use client";

import { useState } from "react";
import Image from "next/image";

/**
 * Poster-scale game artwork for the live screens (LIVE_ROUND and
 * friends) — distinct from the small card-sized <GameArt> already used on
 * RoomAssignedScreen. `artworkUrl` may be null (no art configured), or it
 * may point at a path that simply doesn't have a file behind it yet — see
 * migration 0018's own finding that every seeded game's artwork_url is a
 * plausible-looking path with no real file in /public/games. Either case
 * renders the same intentional, branded fallback: never a broken-image
 * icon, never console error noise, and never a layout shift once art is
 * actually supplied later (the fallback occupies the exact same aspect
 * ratio box).
 */
export function GameArtwork({
  artworkUrl,
  name,
  aspect = "16/10",
}: {
  artworkUrl: string | null | undefined;
  name: string;
  aspect?: string;
}) {
  const [failed, setFailed] = useState(false);
  const showImage = !!artworkUrl && !failed;

  return (
    <div className="rc-live-artwork" style={{ aspectRatio: aspect }}>
      {showImage ? (
        <Image
          src={artworkUrl}
          alt=""
          aria-hidden="true"
          fill
          sizes="(max-width: 480px) 100vw, 480px"
          className="rc-live-artwork-img"
          onError={() => setFailed(true)}
        />
      ) : (
        <div className="rc-live-artwork-fallback" aria-hidden="true">
          <span className="rc-live-artwork-fallback-letter">{name.charAt(0).toUpperCase()}</span>
        </div>
      )}
    </div>
  );
}
