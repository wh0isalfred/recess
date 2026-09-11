import { PlayMark } from "@/components/brand/PlayMark";
import { GameArtwork } from "@/features/live/GameArtwork";
import type { PlayerState } from "@/features/pass/types";
import { RoundTimer } from "./RoundTimer";

/**
 * LIVE_ROUND — "what are we playing, right now." Game name + round count
 * is the single dominant element (poster scale); everything else is
 * secondary. RECESS coordinates the night; it never fabricates in-game
 * state (no alive/dead, no impostor reveal, no drawing/trivia state) —
 * only facts this system genuinely owns are shown here.
 */
export function LiveRoundScreen({ state }: { state: PlayerState }) {
  const game = state.activeGame!;
  const room = state.room!;

  return (
    <div className="rc-live-stage">
      <PlayMark className="rc-live-mark" />
      <GameArtwork artworkUrl={game.artworkUrl} name={game.gameName} />

      <p className="rc-live-eyebrow">{room.label}</p>
      <h1 className="rc-live-heading rc-numeric">{game.gameName.toUpperCase()}</h1>
      <p className="rc-live-round-count rc-numeric">
        ROUND {game.liveRound?.roundIndex} OF {game.plannedRounds}
      </p>

      <RoundTimer startedAt={game.startedAt} durationMinutes={game.durationMinutes} />

      {game.platform === "BROWSER" && game.platformUrl ? (
        <a href={game.platformUrl} className="rc-live-open-game" target="_blank" rel="noreferrer">
          OPEN {game.gameName.toUpperCase()} <span aria-hidden="true">→</span>
        </a>
      ) : null}

      {room.coordinatorAlias ? (
        <p className="rc-live-coordinator">Questions? Ask {room.coordinatorAlias}.</p>
      ) : null}
    </div>
  );
}
