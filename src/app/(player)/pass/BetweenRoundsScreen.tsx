import { PlayMark } from "@/components/brand/PlayMark";
import { GameArtwork } from "@/features/live/GameArtwork";
import type { PlayerState } from "@/features/pass/types";

function factCopy(fact: NonNullable<PlayerState["activeGame"]>["lastRoundResult"]): string {
  if (!fact) return "Round confirmed — details coming.";
  if (fact.yourFact.participation === "DNP") return "YOU DIDN'T PLAY THAT ROUND.";
  if ("role" in fact.yourFact) return `YOU WERE ${fact.yourFact.role.toUpperCase()}.`;
  return `YOUR SCORE: ${fact.yourFact.rawScore.toLocaleString()}.`;
}

/**
 * BETWEEN_ROUNDS — two real substates sharing one screen, distinguished
 * entirely by `activeGame.awaitingGameSettlement` (an authoritative
 * backend fact — never guessed here):
 *
 *   - More rounds remain: the caller's own just-confirmed fact is
 *     dominant, "round N starting soon" is secondary. No championship
 *     points language anywhere — those don't exist until the whole game
 *     settles (see SCORING.md's RAW -> PLACEMENT -> CHAMPIONSHIP chain).
 *   - Ready to settle: "GAME DONE. Scores are being finalized." — never
 *     "another round is coming," and never yourGamePoints, since that
 *     figure genuinely doesn't exist until complete_room_game() runs.
 */
export function BetweenRoundsScreen({ state }: { state: PlayerState }) {
  const game = state.activeGame!;
  const room = state.room!;

  if (game.awaitingGameSettlement) {
    return (
      <div className="rc-live-stage">
        <PlayMark className="rc-live-mark" />
        <GameArtwork artworkUrl={game.artworkUrl} name={game.gameName} />
        <p className="rc-live-eyebrow">{room.label}</p>
        <h1 className="rc-live-heading rc-numeric">GAME DONE.</h1>
        <p className="rc-live-support">Scores are being finalized.</p>
      </div>
    );
  }

  return (
    <div className="rc-live-stage">
      <PlayMark className="rc-live-mark" />
      <GameArtwork artworkUrl={game.artworkUrl} name={game.gameName} />
      <p className="rc-live-eyebrow">{room.label}</p>
      <h1 className="rc-live-heading rc-numeric">{factCopy(game.lastRoundResult)}</h1>
      {game.lastRoundResult?.pending ? (
        <p className="rc-live-pending-tag">A correction is under review for this round.</p>
      ) : null}
      <p className="rc-live-support">
        Round {game.completedRounds + 1} starting soon.
      </p>
    </div>
  );
}
