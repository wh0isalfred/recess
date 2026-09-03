import { RecessWordmark, BrushGesture } from "@/components/brand/RecessWordmark";
import { PlayerAvatar } from "@/components/brand/PlayerAvatar";
import { GameArt } from "@/components/brand/GameArt";
import type { PlayerState } from "@/features/pass/types";
import { isValidWhatsAppGroupUrl } from "@/features/registration/calendar";

const ROSTER_PREVIEW = 6;

function OverflowMenu() {
  return (
    <button type="button" className="rc-room-overflow" aria-label="More options">
      <svg viewBox="0 0 20 6" fill="currentColor" aria-hidden="true">
        <circle cx="2.5" cy="3" r="2.2" />
        <circle cx="10" cy="3" r="2.2" />
        <circle cx="17.5" cy="3" r="2.2" />
      </svg>
    </button>
  );
}

/**
 * Screen 09 — Player Room. Every value here comes from
 * get_player_state()'s ROOM_ASSIGNED payload (migration 0018): room label,
 * occupancy, capacity, the room's own WhatsApp link, the roster (aliases
 * only, this room only), and the up-first game. Nothing is computed or
 * guessed client-side.
 */
export function RoomAssignedScreen({ state }: { state: PlayerState }) {
  const room = state.room!;
  const hasGroup = isValidWhatsAppGroupUrl(room.whatsappGroupUrl);
  const preview = room.roster.slice(0, ROSTER_PREVIEW);
  const overflow = room.roster.length - preview.length;
  const game = state.upFirstGame;

  return (
    <div className="rc-room-stage">
      <header className="rc-room-top">
        <span className="rc-room-mark">
          <RecessWordmark />
          <BrushGesture className="rc-room-gesture" />
          <span className="sr-only">RECESS</span>
        </span>
        <OverflowMenu />
      </header>

      <p className="rc-room-eyebrow">YOU&rsquo;RE IN.</p>
      <h1 className="rc-room-label rc-numeric">{room.label}</h1>

      <p className="rc-room-occupancy">
        <svg viewBox="0 0 16 14" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
          <circle cx="5.5" cy="4" r="2.6" />
          <path d="M1 13c.6-3.4 2.2-5 4.5-5s3.9 1.6 4.5 5" />
          <circle cx="11.5" cy="4.8" r="2" />
          <path d="M11 8.3c1.8.2 3 1.6 3.5 4.2" />
        </svg>
        <span className="rc-numeric">{room.occupancy}</span> / <span className="rc-numeric">{room.capacity ?? "—"}</span> PLAYERS
      </p>

      {hasGroup ? (
        <a href={room.whatsappGroupUrl!} className="rc-room-whatsapp" target="_blank" rel="noreferrer">
          <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path d="M10 1.7A8.3 8.3 0 0 0 2.9 14.4L1.7 18.3l4-1.2A8.3 8.3 0 1 0 10 1.7Zm4.8 11.7c-.2.6-1.2 1.1-1.7 1.2-.4.1-1 .1-1.6-.1-.4-.1-.9-.3-1.5-.6-2.6-1.1-4.3-3.7-4.5-3.9-.1-.2-1.1-1.4-1.1-2.7s.7-1.9.9-2.2c.2-.2.5-.3.6-.3h.5c.2 0 .4 0 .6.4l.8 1.9c.1.2.1.3 0 .5l-.4.5-.3.3c-.1.1-.2.3-.1.5.2.3.8 1.3 1.7 2.1 1.2 1 2.1 1.4 2.4 1.5.3.1.4.1.6-.1l.6-.7c.2-.3.4-.2.6-.1l1.7.8c.2.1.4.2.4.3.1.2.1.7-.1 1.3Z" />
          </svg>
          JOIN ROOM WHATSAPP <span aria-hidden="true">→</span>
        </a>
      ) : (
        <p className="rc-room-whatsapp rc-room-whatsapp--pending" aria-live="polite">
          Room WhatsApp link coming soon
        </p>
      )}

      {game ? (
        <div className="rc-room-upfirst" aria-disabled="true">
          <span className="rc-room-upfirst-label">UP FIRST</span>
          <div className="rc-room-upfirst-row">
            <GameArt artworkUrl={game.artworkUrl} name={game.name} size={3} />
            <div className="rc-room-upfirst-info">
              <span className="rc-room-upfirst-name">{game.name}</span>
              {/* No per-game scheduled start time exists in the schema yet —
                  see migration 0018's report. A truthful status, not a
                  fabricated clock time. */}
              <span className="rc-room-upfirst-status">Up first</span>
              <span className="rc-room-upfirst-chip">GET READY</span>
            </div>
          </div>
        </div>
      ) : null}

      <section className="rc-room-roster">
        <h2 className="rc-room-roster-title">YOUR ROOM</h2>
        <ul className="rc-room-roster-list">
          {preview.map((p, i) => (
            <li key={i} className="rc-room-roster-row">
              <PlayerAvatar alias={p.alias} size={1.75} />
              <span className="rc-room-roster-alias rc-numeric">{p.alias}</span>
              {p.alias === state.player.alias ? <span className="rc-room-you-badge">YOU</span> : null}
            </li>
          ))}
        </ul>
        {overflow > 0 ? <p className="rc-room-roster-more">+ {overflow} MORE</p> : null}
      </section>

      <div className="rc-room-footer">
        <p className="rc-room-footer-label rc-numeric">{room.label}</p>
        <p className="rc-room-footer-copy">STAY HERE. WE&rsquo;LL TELL YOU WHEN IT&rsquo;S TIME.</p>
      </div>
    </div>
  );
}
