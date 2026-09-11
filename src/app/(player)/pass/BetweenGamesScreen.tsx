import { PlayMark } from "@/components/brand/PlayMark";
import { GameArtwork } from "@/features/live/GameArtwork";
import type { PlayerState } from "@/features/pass/types";

/**
 * BETWEEN_GAMES — the just-finished game is genuinely settled (its
 * points and, when leaderboard_visibility allows, its room placement are
 * both real, ledger-derived facts by this point). The next game is the
 * clear forward-looking element — "what's happening next," pulled
 * forward visually by its own artwork.
 */
export function BetweenGamesScreen({ state }: { state: PlayerState }) {
  const last = state.lastCompletedGame;
  const next = state.nextGame;

  return (
    <div className="rc-live-stage">
      <PlayMark className="rc-live-mark" />

      {last ? (
        <>
          <h1 className="rc-live-heading rc-numeric">{last.gameName.toUpperCase()} DONE.</h1>
          <p className="rc-live-points rc-numeric">{last.yourGamePoints} points</p>
          {last.roomPlacementThisGame !== null ? (
            <p className="rc-live-support">Room placement: {last.roomPlacementThisGame}</p>
          ) : null}
        </>
      ) : (
        <h1 className="rc-live-heading rc-numeric">GAME DONE.</h1>
      )}

      {next ? (
        <div className="rc-live-upnext">
          <p className="rc-live-upnext-label">UP NEXT</p>
          <GameArtwork artworkUrl={next.artworkUrl} name={next.name} aspect="16/9" />
          <p className="rc-live-upnext-name rc-numeric">{next.name}</p>
        </div>
      ) : null}
    </div>
  );
}
