import { Panel } from "./Surface";
import { StatusBadge } from "./StatusBadge";

/**
 * The next edition, as a player sees it on their Event Pass and as an admin
 * sees it on the dashboard. The countdown is the loudest thing on it, because
 * before the night begins the only question is how long left.
 */
export function EventCard({
  name,
  weekday,
  date,
  time,
  timezone,
  daysToGo,
  status,
  registered,
}: {
  name: string;
  weekday: string;
  date: string;
  time: string;
  timezone: string;
  daysToGo?: number;
  status: string;
  registered?: string;
}) {
  return (
    <Panel className="p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="rc-label">Next RECESS</p>
          <h3 className="mt-1 font-display text-rc-md">{name}</h3>
        </div>
        <StatusBadge tone="info">{status}</StatusBadge>
      </div>

      <div className="mt-5 flex items-end justify-between gap-4">
        <div>
          <p className="font-display text-rc-lg">
            {weekday} {date}
          </p>
          <p className="rc-numeric text-rc-base text-fg-soft">
            {time} <span className="text-accent-text">{timezone}</span>
          </p>
        </div>

        {daysToGo !== undefined ? (
          <div className="text-right">
            <p className="rc-numeric font-display text-rc-xl text-accent-text">
              {String(daysToGo).padStart(2, "0")}
            </p>
            <p className="rc-label">
              {daysToGo === 1 ? "day to go" : "days to go"}
            </p>
          </div>
        ) : null}
      </div>

      {registered ? (
        <p className="mt-4 border-t-[length:var(--hairline)] border-fg-line pt-4 text-rc-sm text-fg-soft">
          {registered}
        </p>
      ) : null}
    </Panel>
  );
}
