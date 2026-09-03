import type { ReactNode } from "react";
import { RecessWordmark, BrushGesture } from "@/components/brand/RecessWordmark";
import type { PlayerState } from "@/features/pass/types";
import { countdownTo } from "@/features/pass/countdown";
import { greetingFor } from "@/features/pass/greeting";
import { platformLabel, gameIconKind } from "@/features/pass/gameLabels";
import { formatEventDate, formatEventTime, isValidWhatsAppGroupUrl } from "@/features/registration/calendar";

function OverflowMenu() {
  return (
    <button type="button" className="rc-evp-overflow" aria-label="More options">
      <svg viewBox="0 0 20 6" fill="currentColor" aria-hidden="true">
        <circle cx="2.5" cy="3" r="2.2" />
        <circle cx="10" cy="3" r="2.2" />
        <circle cx="17.5" cy="3" r="2.2" />
      </svg>
    </button>
  );
}

function GameIcon({ kind }: { kind: ReturnType<typeof gameIconKind> }) {
  const paths: Record<string, ReactNode> = {
    crew: (
      <path d="M12 4a4 4 0 0 1 4 4v3.5a2 2 0 0 1-2 2h-.4l.6 5H9.8l.6-5H10a2 2 0 0 1-2-2V8a4 4 0 0 1 4-4Z" />
    ),
    pencil: <path d="M5 16.5 15.5 6 18 8.5 7.5 19 4 20l1-3.5Z" />,
    bolt: <path d="M13 2 4 13h6l-1 9 9-11h-6l1-9Z" />,
    dot: <circle cx="12" cy="12" r="6" />,
  };
  return (
    <svg viewBox="0 0 24 24" className="rc-evp-game-icon" fill="currentColor" aria-hidden="true">
      {paths[kind]}
    </svg>
  );
}

export function EventPassScreen({ state }: { state: PlayerState }) {
  const { event, player, games } = state;
  const countdown = countdownTo(event.startsAt, event.timezone);
  const hasGroup = isValidWhatsAppGroupUrl(event.whatsappGroupUrl);

  return (
    <div className="rc-evp-stage">
      <header className="rc-evp-top">
        <span className="rc-evp-mark">
          <RecessWordmark />
          <BrushGesture className="rc-evp-gesture" />
          <span className="sr-only">RECESS</span>
        </span>
        <OverflowMenu />
      </header>

      <p className="rc-evp-greeting">
        {greetingFor(event.timezone)}
        <br />
        <span className="rc-evp-alias rc-numeric">{player.alias}.</span>
      </p>

      <div className="rc-evp-card">
        <div className="rc-evp-card-main">
          <span className="rc-evp-card-label">NEXT RECESS</span>
          <p className="rc-evp-card-date">{formatEventDate(event.startsAt, event.timezone)}</p>
          <p className="rc-evp-card-time">
            {formatEventTime(event.startsAt, event.timezone)} {event.timezoneLabel}
          </p>
          <span className="rc-evp-status-badge">YOU&rsquo;RE IN</span>
        </div>
        <div className="rc-evp-countdown">
          {countdown.kind === "future" ? (
            <>
              <span className="rc-evp-countdown-num rc-numeric">{String(countdown.days).padStart(2, "0")}</span>
              <span className="rc-evp-countdown-label">
                DAYS
                <br />
                TO GO
              </span>
            </>
          ) : countdown.kind === "today" ? (
            <span className="rc-evp-countdown-today">TODAY</span>
          ) : (
            <span className="rc-evp-countdown-today">SOON</span>
          )}
        </div>
      </div>

      {games && games.length > 0 ? (
        <section className="rc-evp-ready">
          <h2 className="rc-evp-ready-title">GET READY</h2>
          <ul className="rc-evp-game-list">
            {games.map((g) => (
              <li key={g.slug} className="rc-evp-game-row">
                <span className="rc-evp-game-icon-wrap">
                  <GameIcon kind={gameIconKind(g.slug)} />
                </span>
                <span className="rc-evp-game-name">{g.name}</span>
                <span className="rc-evp-game-platform">{platformLabel(g.platform)}</span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {hasGroup ? (
        <a href={event.whatsappGroupUrl!} className="rc-evp-whatsapp" target="_blank" rel="noreferrer">
          JOIN WHATSAPP GROUP
        </a>
      ) : (
        <p className="rc-evp-whatsapp rc-evp-whatsapp--pending" aria-live="polite">
          WhatsApp group link coming soon
        </p>
      )}
    </div>
  );
}
