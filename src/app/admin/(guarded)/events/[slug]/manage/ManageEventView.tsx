"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { fetchEventOverview, purgePreEventEvent, updateEventGame } from "@/features/admin/actions";
import type { EventGameConfig, EventOverview } from "@/features/admin/types";

const PURGEABLE_STATUSES = new Set(["DRAFT", "REGISTRATION", "REGISTRATION_CLOSED"]);

function GameRow({ slug, game }: { slug: string; game: EventGameConfig }) {
  const [duration, setDuration] = useState(game.durationMinutes?.toString() ?? "");
  const [rounds, setRounds] = useState(game.plannedRounds.toString());
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setSaving(true);
    setError(null);
    setSaved(false);
    const result = await updateEventGame(slug, game.id, {
      durationMinutes: duration.trim() === "" ? null : Number(duration),
      plannedRounds: rounds.trim() === "" ? null : Number(rounds),
    });
    setSaving(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
    <li className="rc-admin-manage-game-row">
      <span className="rc-admin-manage-game-name">
        {game.position}. {game.gameName}
      </span>
      <label className="rc-admin-game-config-field">
        <span>Duration (min)</span>
        <input
          type="number"
          min={1}
          value={duration}
          onChange={(e) => setDuration(e.target.value)}
          placeholder="not set"
        />
      </label>
      <label className="rc-admin-game-config-field">
        <span>Planned rounds</span>
        <input type="number" min={1} value={rounds} onChange={(e) => setRounds(e.target.value)} />
      </label>
      <button type="button" className="rc-admin-configure" onClick={save} disabled={saving}>
        {saving ? "SAVING…" : saved ? "SAVED" : "SAVE"}
      </button>
      {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
    </li>
  );
}

type DangerPhase = "idle" | "warning" | "confirmed-with-registrations" | "typing-slug";

function DangerZone({
  slug,
  status,
  initialRegisteredCount,
  initialCheckedInCount,
}: {
  slug: string;
  status: string;
  initialRegisteredCount: number;
  initialCheckedInCount: number;
}) {
  const router = useRouter();
  const [phase, setPhase] = useState<DangerPhase>("idle");
  const [registeredCount, setRegisteredCount] = useState(initialRegisteredCount);
  const [checkedInCount, setCheckedInCount] = useState(initialCheckedInCount);
  const [typedSlug, setTypedSlug] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!PURGEABLE_STATUSES.has(status)) {
    return (
      <section className="rc-admin-card rc-admin-danger-zone">
        <h2 className="rc-admin-card-title">DANGER ZONE</h2>
        <p className="rc-admin-empty">
          This event is {status.replace("_", " ").toLowerCase()} and can no longer be permanently deleted — cancel
          it instead if it needs to be withdrawn.
        </p>
      </section>
    );
  }

  const beginDelete = async () => {
    setError(null);
    setLoading(true);
    // Fresh, authoritative counts at the actual moment of deciding —
    // not whatever was on the page whenever it happened to load.
    const result = await fetchEventOverview(slug);
    setLoading(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    setRegisteredCount(result.data.counts.registered);
    setCheckedInCount(result.data.counts.checkedIn);
    setPhase(result.data.counts.registered > 0 ? "confirmed-with-registrations" : "typing-slug");
  };

  const finalDelete = async () => {
    setLoading(true);
    setError(null);
    const result = await purgePreEventEvent(slug);
    setLoading(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    router.push("/admin/events");
  };

  return (
    <section className="rc-admin-card rc-admin-danger-zone">
      <h2 className="rc-admin-card-title">DANGER ZONE</h2>

      {phase === "idle" ? (
        <>
          <p className="rc-admin-empty">
            Permanently deleting this event removes it and all its registrations. This cannot be undone.
          </p>
          <button type="button" className="rc-admin-danger-btn" onClick={() => setPhase("warning")}>
            Delete event…
          </button>
        </>
      ) : null}

      {phase === "warning" ? (
        <div className="rc-admin-danger-confirm">
          <p className="rc-admin-error rc-admin-error--inline">
            This permanently deletes &ldquo;{slug}&rdquo; and cannot be undone.
          </p>
          {checkedInCount > 0 ? (
            <p className="rc-admin-empty">
              People have already checked in for this event, so it can no longer be permanently deleted — cancel it
              instead.
            </p>
          ) : (
            <div className="rc-admin-danger-actions">
              <button type="button" className="rc-admin-configure" onClick={() => setPhase("idle")}>
                Cancel
              </button>
              <button type="button" className="rc-admin-danger-btn" onClick={beginDelete} disabled={loading}>
                {loading ? "Checking…" : "Continue"}
              </button>
            </div>
          )}
        </div>
      ) : null}

      {phase === "confirmed-with-registrations" ? (
        <div className="rc-admin-danger-confirm">
          <p className="rc-admin-error rc-admin-error--inline">
            {registeredCount} {registeredCount === 1 ? "person is" : "people are"} already registered. Deleting this
            event will permanently remove their registrations and event access.
          </p>
          <div className="rc-admin-danger-actions">
            <button type="button" className="rc-admin-configure" onClick={() => setPhase("idle")}>
              Cancel
            </button>
            <button type="button" className="rc-admin-danger-btn" onClick={() => setPhase("typing-slug")}>
              I understand — continue
            </button>
          </div>
        </div>
      ) : null}

      {phase === "typing-slug" ? (
        <div className="rc-admin-danger-confirm">
          <p className="rc-admin-empty">
            Type the event slug (<strong>{slug}</strong>) to confirm permanent deletion.
          </p>
          <input
            className="rc-admin-danger-slug-input"
            value={typedSlug}
            onChange={(e) => setTypedSlug(e.target.value)}
            placeholder={slug}
            autoComplete="off"
          />
          <div className="rc-admin-danger-actions">
            <button type="button" className="rc-admin-configure" onClick={() => setPhase("idle")}>
              Cancel
            </button>
            <button
              type="button"
              className="rc-admin-danger-btn"
              onClick={finalDelete}
              disabled={typedSlug !== slug || loading}
            >
              {loading ? "Deleting…" : "Permanently delete this event"}
            </button>
          </div>
        </div>
      ) : null}

      {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
    </section>
  );
}

export function ManageEventView({
  slug,
  event,
  registeredCount,
  checkedInCount,
  games,
}: {
  slug: string;
  event: EventOverview["event"];
  registeredCount: number;
  checkedInCount: number;
  games: EventGameConfig[];
}) {
  return (
    <main className="rc-admin-page">
      <header className="rc-admin-header">
        <h1 className="rc-admin-title">Manage — {event.name}</h1>
      </header>

      <section className="rc-admin-card">
        <h2 className="rc-admin-card-title">GAMES</h2>
        {games.length > 0 ? (
          <ul className="rc-admin-manage-game-list">
            {games.map((g) => (
              <GameRow key={g.id} slug={slug} game={g} />
            ))}
          </ul>
        ) : (
          <p className="rc-admin-empty">No games configured for this event yet.</p>
        )}
        <p className="rc-admin-empty">
          Duration and planned rounds are configuration, not a running timer — a room&rsquo;s actual game clock is
          anchored to when its coordinator starts that game.
        </p>
      </section>

      <DangerZone
        slug={slug}
        status={event.status}
        initialRegisteredCount={registeredCount}
        initialCheckedInCount={checkedInCount}
      />
    </main>
  );
}
