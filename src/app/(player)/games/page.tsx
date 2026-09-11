import { Surface } from "@/components/ui/Surface";
import { GameArtwork } from "@/features/live/GameArtwork";
import { fetchMyGameProgress } from "@/features/live/actions";

/**
 * /games — the map of the night, not a live feed (that's /pass). The
 * event's configured games in order, each honestly marked from the
 * player's own room's progression — never another room's, never
 * controls a coordinator/admin would use. Before room assignment, every
 * item simply reads PENDING rather than pretending room-specific
 * progress exists yet.
 */
export default async function GamesPage() {
  const result = await fetchMyGameProgress();

  if (!result.ok) {
    return (
      <Surface as="main" grain="low" className="rc-games">
        <p className="rc-games-error">{result.message}</p>
      </Surface>
    );
  }

  return (
    <Surface as="main" grain="low" className="rc-games">
      <div className="rc-games-stage">
        <h1 className="rc-games-heading">TONIGHT&rsquo;S GAMES</h1>
        <ol className="rc-games-list">
          {result.data.map((game) => (
            <li key={game.slug} className="rc-games-row" data-status={game.status}>
              <GameArtwork artworkUrl={game.artworkUrl} name={game.name} aspect="1/1" />
              <div className="rc-games-row-info">
                <p className="rc-games-row-name rc-numeric">{game.name}</p>
                <p className="rc-games-row-status">
                  {game.status === "COMPLETE"
                    ? game.yourGamePoints !== null
                      ? `Done · ${game.yourGamePoints} points`
                      : "Done"
                    : game.status === "LIVE"
                      ? `Live · round ${game.completedRounds} of ${game.plannedRounds}`
                      : "Upcoming"}
                </p>
              </div>
            </li>
          ))}
        </ol>
      </div>
    </Surface>
  );
}
