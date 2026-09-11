import { Surface } from "@/components/ui/Surface";
import { fetchMyRoomStandings } from "@/features/live/actions";

/**
 * /players — your room, your people, standings only when
 * leaderboard_visibility permits. Never a global directory, never
 * another room's roster, never a registrationId or any staff-only
 * field. get_my_room_standings() itself decides whether standings exist
 * at all for the caller right now — this page never second-guesses that
 * server decision.
 */
export default async function PlayersPage() {
  const result = await fetchMyRoomStandings();

  if (!result.ok) {
    return (
      <Surface as="main" grain="low" className="rc-players">
        <p className="rc-players-error">{result.message}</p>
      </Surface>
    );
  }

  const { room, standings } = result.data;

  if (!room) {
    return (
      <Surface as="main" grain="low" className="rc-players">
        <div className="rc-players-stage">
          <h1 className="rc-players-heading">YOUR PEOPLE</h1>
          <p className="rc-players-support">You&rsquo;ll see your room here once you&rsquo;re assigned one.</p>
        </div>
      </Surface>
    );
  }

  return (
    <Surface as="main" grain="low" className="rc-players">
      <div className="rc-players-stage">
        <h1 className="rc-players-heading rc-numeric">{room}</h1>
        {standings ? (
          <ol className="rc-players-standings">
            {standings.map((row) => (
              <li key={row.alias} className="rc-players-row">
                <span className="rc-players-placement rc-numeric">{row.placement}</span>
                <span className="rc-players-alias">{row.alias}</span>
                <span className="rc-players-points rc-numeric">{row.totalPoints}</span>
              </li>
            ))}
          </ol>
        ) : (
          <p className="rc-players-support">Standings aren&rsquo;t shown yet — check back later tonight.</p>
        )}
      </div>
    </Surface>
  );
}
