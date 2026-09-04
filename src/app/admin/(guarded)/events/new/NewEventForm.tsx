"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { addEventGame, createEvent, upsertRoom } from "@/features/admin/actions";
import type { GameLibraryEntry } from "@/features/admin/types";

/**
 * RECESS runs on Africa/Lagos, which has no DST — a fixed UTC+1 all year.
 * Building the ISO string with an explicit "+01:00" offset means the browser
 * parses it as that exact instant regardless of the visitor's own local
 * timezone, with no date-arithmetic or timezone-library needed for what is,
 * in practice, always the same offset.
 */
function toLagosIso(date: string, time: string): string | null {
  if (!date || !time) return null;
  return `${date}T${time}:00+01:00`;
}

type RoomDraft = { label: string; capacity: string };

/**
 * One page, three sections, a review step — not a paginated wizard.
 * Creating the event itself is one RPC call (admin_create_event, 0019);
 * games and rooms are added with one call per item afterward, since that is
 * exactly what admin_add_event_game() and admin_upsert_room() already do
 * one row at a time. There is no cross-step transaction wrapping all of
 * this — a partial failure midway leaves a real, inspectable DRAFT event
 * (never LIVE, never CHECK_IN) that the Overview/Rooms pages this task
 * already built can finish configuring, rather than a phantom half-created
 * event with nothing to point at.
 */
export function NewEventForm({ games }: { games: GameLibraryEntry[] }) {
  const router = useRouter();

  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [slugTouched, setSlugTouched] = useState(false);
  const [date, setDate] = useState("");
  const [time, setTime] = useState("20:00");
  const [registrationOpenDate, setRegistrationOpenDate] = useState("");
  const [registrationOpenTime, setRegistrationOpenTime] = useState("09:00");
  const [registrationCloseDate, setRegistrationCloseDate] = useState("");
  const [registrationCloseTime, setRegistrationCloseTime] = useState("18:00");
  const [checkinOpenTime, setCheckinOpenTime] = useState("19:30");
  const [checkinCloseTime, setCheckinCloseTime] = useState("21:30");
  const [capacity, setCapacity] = useState("30");
  const [whatsapp, setWhatsapp] = useState("");
  const [selectedGames, setSelectedGames] = useState<string[]>([]);
  const [rooms, setRooms] = useState<RoomDraft[]>([{ label: "ROOM 01", capacity: "15" }]);

  const [reviewing, setReviewing] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleNameChange = (value: string) => {
    setName(value);
    if (!slugTouched) {
      setSlug(
        value
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-+|-+$/g, ""),
      );
    }
  };

  const toggleGame = (id: string) => {
    setSelectedGames((prev) => (prev.includes(id) ? prev.filter((g) => g !== id) : [...prev, id]));
  };

  const moveGame = (index: number, dir: -1 | 1) => {
    setSelectedGames((prev) => {
      const next = [...prev];
      const target = index + dir;
      if (target < 0 || target >= next.length) return prev;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  };

  const addRoom = () => setRooms((prev) => [...prev, { label: `ROOM ${String(prev.length + 1).padStart(2, "0")}`, capacity: "15" }]);
  const removeRoom = (i: number) => setRooms((prev) => prev.filter((_, idx) => idx !== i));
  const updateRoom = (i: number, patch: Partial<RoomDraft>) =>
    setRooms((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

  const canReview =
    name.trim() !== "" &&
    slug.trim() !== "" &&
    date !== "" &&
    time !== "" &&
    capacity.trim() !== "" &&
    Number(capacity) > 0 &&
    selectedGames.length > 0;

  const handleCreate = async () => {
    if (submitting) return;
    setSubmitting(true);
    setError(null);

    const startsAt = toLagosIso(date, time);
    if (!startsAt) {
      setSubmitting(false);
      setError("Event date and time are required.");
      return;
    }

    const created = await createEvent({
      slug,
      name,
      startsAt,
      timezone: "Africa/Lagos",
      timezoneLabel: "WAT",
      registrationOpensAt: toLagosIso(registrationOpenDate, registrationOpenTime),
      registrationClosesAt: toLagosIso(registrationCloseDate, registrationCloseTime),
      checkinOpensAt: toLagosIso(date, checkinOpenTime),
      checkinClosesAt: toLagosIso(date, checkinCloseTime),
      capacity: Number(capacity),
      whatsappGroupUrl: whatsapp.trim() === "" ? null : whatsapp.trim(),
    });

    if (!created.ok) {
      setSubmitting(false);
      setError(created.message);
      return;
    }

    for (let i = 0; i < selectedGames.length; i++) {
      const result = await addEventGame(slug, selectedGames[i], i + 1);
      if (!result.ok) {
        setSubmitting(false);
        setError(`Event was created, but adding a game failed: ${result.message} You can finish this on the event's page.`);
        router.push(`/admin/events/${slug}/overview`);
        return;
      }
    }

    for (const room of rooms) {
      if (room.label.trim() === "") continue;
      const result = await upsertRoom(slug, {
        roomId: null,
        label: room.label.trim(),
        capacity: room.capacity.trim() === "" ? null : Number(room.capacity),
        whatsappGroupUrl: null,
      });
      if (!result.ok) {
        setSubmitting(false);
        setError(`Event and games were created, but a room failed: ${result.message} You can finish this on the Rooms page.`);
        router.push(`/admin/events/${slug}/rooms`);
        return;
      }
    }

    router.push(`/admin/events/${slug}/overview`);
  };

  if (reviewing) {
    return (
      <div className="rc-admin-card">
        <h2 className="rc-admin-card-title">REVIEW</h2>
        <dl className="rc-admin-review">
          <dt>Name</dt><dd>{name}</dd>
          <dt>Slug</dt><dd>{slug}</dd>
          <dt>Starts</dt><dd>{date} at {time} WAT</dd>
          <dt>Registration</dt>
          <dd>
            {registrationOpenDate ? `${registrationOpenDate} ${registrationOpenTime}` : "not set"} →{" "}
            {registrationCloseDate ? `${registrationCloseDate} ${registrationCloseTime}` : "not set"}
          </dd>
          <dt>Check-in</dt><dd>{checkinOpenTime} → {checkinCloseTime} WAT, event day</dd>
          <dt>Capacity</dt><dd>{capacity}</dd>
          <dt>WhatsApp</dt><dd>{whatsapp.trim() || "not set"}</dd>
          <dt>Games</dt>
          <dd>
            {selectedGames.map((id, i) => (
              <span key={id}>
                {i + 1}. {games.find((g) => g.id === id)?.name}
                {i < selectedGames.length - 1 ? ", " : ""}
              </span>
            ))}
          </dd>
          <dt>Rooms</dt>
          <dd>{rooms.map((r) => `${r.label} (${r.capacity || "no capacity"})`).join(", ")}</dd>
        </dl>
        {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
        <div className="rc-admin-review-actions">
          <button type="button" className="rc-admin-configure" onClick={() => setReviewing(false)} disabled={submitting}>
            ← BACK
          </button>
          <button type="button" className="rc-admin-drawer-save" onClick={handleCreate} disabled={submitting}>
            {submitting ? "CREATING…" : "CREATE EVENT"}
          </button>
        </div>
        <p className="rc-admin-empty" style={{ marginTop: "0.75rem" }}>
          The event is created as DRAFT — it will not accept registrations until you open registration
          from its Overview page.
        </p>
      </div>
    );
  }

  return (
    <div className="rc-admin-builder">
      <section className="rc-admin-card">
        <h2 className="rc-admin-card-title">EVENT DETAILS</h2>
        <div className="rc-admin-builder-grid">
          <label className="rc-admin-field">
            <span>Name</span>
            <input value={name} onChange={(e) => handleNameChange(e.target.value)} placeholder="RECESS — September 2026" />
          </label>
          <label className="rc-admin-field">
            <span>Slug</span>
            <input value={slug} onChange={(e) => { setSlug(e.target.value); setSlugTouched(true); }} placeholder="recess-01" />
          </label>
          <label className="rc-admin-field">
            <span>Date</span>
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>Start time (WAT)</span>
            <input type="time" value={time} onChange={(e) => setTime(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>Capacity</span>
            <input type="number" min={1} value={capacity} onChange={(e) => setCapacity(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>Main WhatsApp group URL</span>
            <input value={whatsapp} onChange={(e) => setWhatsapp(e.target.value)} placeholder="https://chat.whatsapp.com/..." />
          </label>
        </div>
      </section>

      <section className="rc-admin-card">
        <h2 className="rc-admin-card-title">REGISTRATION &amp; CHECK-IN WINDOWS</h2>
        <div className="rc-admin-builder-grid">
          <label className="rc-admin-field">
            <span>Registration opens</span>
            <input type="date" value={registrationOpenDate} onChange={(e) => setRegistrationOpenDate(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>&nbsp;</span>
            <input type="time" value={registrationOpenTime} onChange={(e) => setRegistrationOpenTime(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>Registration closes</span>
            <input type="date" value={registrationCloseDate} onChange={(e) => setRegistrationCloseDate(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>&nbsp;</span>
            <input type="time" value={registrationCloseTime} onChange={(e) => setRegistrationCloseTime(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>Check-in opens (event day, WAT)</span>
            <input type="time" value={checkinOpenTime} onChange={(e) => setCheckinOpenTime(e.target.value)} />
          </label>
          <label className="rc-admin-field">
            <span>Check-in closes (event day, WAT)</span>
            <input type="time" value={checkinCloseTime} onChange={(e) => setCheckinCloseTime(e.target.value)} />
          </label>
        </div>
        <p className="rc-admin-empty">
          A registration window is required before registration can open. Check-in windows are optional here —
          set them later on the event&rsquo;s Overview page if you&rsquo;d rather decide closer to the day.
        </p>
      </section>

      <section className="rc-admin-card">
        <h2 className="rc-admin-card-title">GAMES</h2>
        <ul className="rc-admin-game-picker">
          {games.map((g) => (
            <li key={g.id} className="rc-admin-game-picker-row">
              <label>
                <input type="checkbox" checked={selectedGames.includes(g.id)} onChange={() => toggleGame(g.id)} />
                {g.name} <span className="rc-admin-room-coordinator">({g.platform})</span>
              </label>
            </li>
          ))}
          {games.length === 0 ? <p className="rc-admin-empty">No active games in the library.</p> : null}
        </ul>
        {selectedGames.length > 0 ? (
          <ol className="rc-admin-game-order">
            {selectedGames.map((id, i) => (
              <li key={id}>
                {i + 1}. {games.find((g) => g.id === id)?.name}
                <button type="button" onClick={() => moveGame(i, -1)} disabled={i === 0} aria-label="Move up">↑</button>
                <button type="button" onClick={() => moveGame(i, 1)} disabled={i === selectedGames.length - 1} aria-label="Move down">↓</button>
              </li>
            ))}
          </ol>
        ) : null}
      </section>

      <section className="rc-admin-card">
        <h2 className="rc-admin-card-title">ROOMS</h2>
        <div className="rc-admin-room-drafts">
          {rooms.map((room, i) => (
            <div key={i} className="rc-admin-room-draft-row">
              <input value={room.label} onChange={(e) => updateRoom(i, { label: e.target.value })} placeholder="Room label" />
              <input
                type="number"
                min={1}
                value={room.capacity}
                onChange={(e) => updateRoom(i, { capacity: e.target.value })}
                placeholder="Capacity"
              />
              <button type="button" onClick={() => removeRoom(i)} aria-label="Remove room">✕</button>
            </div>
          ))}
        </div>
        <button type="button" className="rc-admin-configure" onClick={addRoom}>+ ADD ROOM</button>
        <p className="rc-admin-empty">Room WhatsApp links can be added later from the Rooms page.</p>
      </section>

      <button type="button" className="rc-admin-drawer-save rc-admin-builder-review" disabled={!canReview} onClick={() => setReviewing(true)}>
        REVIEW &amp; CREATE →
      </button>
    </div>
  );
}
