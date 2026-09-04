"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  assignCoordinator,
  assignWaitingPlayers,
  fetchRoomMembers,
  upsertRoom,
} from "@/features/admin/actions";
import type { AdminRoom, RoomMember, RoomsOverview } from "@/features/admin/types";
import { PlayerAvatar } from "@/components/brand/PlayerAvatar";

type DrawerState = { mode: "create" } | { mode: "edit"; room: AdminRoom } | null;

function whatsappBadge(room: AdminRoom) {
  return room.whatsappGroupUrl ? (
    <span className="rc-admin-room-badge rc-admin-tone-go">WhatsApp ✓</span>
  ) : (
    <span className="rc-admin-room-badge rc-admin-tone-warn">WhatsApp missing</span>
  );
}

function roomStatusLabel(room: AdminRoom): string {
  if (room.capacity === null) return "NOT READY";
  if (room.occupancy >= room.capacity) return "FULL";
  return "";
}

function RoomDrawer({ slug: drawerSlug, state, onClose, onSaved }: { slug: string; state: DrawerState; onClose: () => void; onSaved: () => void }) {
  const editing = state?.mode === "edit" ? state.room : null;
  const [label, setLabel] = useState(editing?.label ?? "");
  const [capacity, setCapacity] = useState(editing?.capacity?.toString() ?? "");
  const [whatsapp, setWhatsapp] = useState(editing?.whatsappGroupUrl ?? "");
  const [coordinatorId, setCoordinatorId] = useState(editing?.coordinator?.userId ?? "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!state) return null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await upsertRoom(drawerSlug, {
        roomId: editing?.id ?? null,
        label,
        capacity: capacity.trim() === "" ? null : Number(capacity),
        whatsappGroupUrl: whatsapp.trim() === "" ? null : whatsapp.trim(),
      });
      if (!result.ok) {
        setSubmitting(false);
        setError(result.message);
        return;
      }
      if (editing) {
        const coordResult = await assignCoordinator(
          drawerSlug,
          editing.id,
          coordinatorId.trim() === "" ? null : coordinatorId.trim(),
        );
        if (!coordResult.ok) {
          setSubmitting(false);
          setError(coordResult.message);
          return;
        }
      }
      setSubmitting(false);
      onSaved();
    } catch {
      setSubmitting(false);
      setError("Something went wrong. Please try again.");
    }
  };

  return (
    <div className="rc-admin-drawer-backdrop" onClick={onClose}>
      <div className="rc-admin-drawer" onClick={(e) => e.stopPropagation()}>
        <div className="rc-admin-drawer-head">
          <h2>{editing ? `Edit ${editing.label}` : "Add room"}</h2>
          <button type="button" className="rc-admin-drawer-close" onClick={onClose} aria-label="Close">✕</button>
        </div>
        <form onSubmit={submit} className="rc-admin-drawer-form">
          <label className="rc-admin-field">
            <span>Label</span>
            <input value={label} onChange={(e) => setLabel(e.target.value)} required maxLength={40} />
          </label>
          <label className="rc-admin-field">
            <span>Capacity</span>
            <input
              type="number"
              min={1}
              value={capacity}
              onChange={(e) => setCapacity(e.target.value)}
              placeholder="Not set — room won't receive check-in assignments"
            />
          </label>
          <label className="rc-admin-field">
            <span>WhatsApp group URL</span>
            <input
              value={whatsapp}
              onChange={(e) => setWhatsapp(e.target.value)}
              placeholder="https://chat.whatsapp.com/..."
            />
          </label>
          {editing ? (
            <label className="rc-admin-field">
              <span>Coordinator (staff user ID)</span>
              <input
                value={coordinatorId}
                onChange={(e) => setCoordinatorId(e.target.value)}
                placeholder="Leave blank to remove"
              />
            </label>
          ) : null}
          {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
          <button type="submit" className="rc-admin-drawer-save" disabled={submitting}>
            {submitting ? "SAVING…" : "SAVE ROOM"}
          </button>
        </form>
      </div>
    </div>
  );
}

function MembersPanel({ roomId, onClose }: { roomId: string; onClose: () => void }) {
  const [members, setMembers] = useState<RoomMember[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchRoomMembers(roomId).then((r) => {
      if (cancelled) return;
      if (r.ok) setMembers(r.data);
      else setError(r.message);
    });
    return () => {
      cancelled = true;
    };
  }, [roomId]);

  return (
    <div className="rc-admin-members">
      <div className="rc-admin-members-head">
        <span>PLAYERS IN THIS ROOM</span>
        <button type="button" onClick={onClose} aria-label="Close">✕</button>
      </div>
      {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
      {members === null && !error ? <p className="rc-admin-empty">Loading…</p> : null}
      {members?.length === 0 ? <p className="rc-admin-empty">No players yet.</p> : null}
      <ul className="rc-admin-members-list">
        {members?.map((m) => (
          <li key={m.alias} className="rc-admin-members-row">
            <PlayerAvatar alias={m.alias} size={1.5} />
            <span className="rc-numeric">{m.alias}</span>
            <span className="rc-admin-members-number rc-numeric">#{String(m.playerNumber).padStart(3, "0")}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function RoomsClient({ slug, initial }: { slug: string; initial: RoomsOverview }) {
  const router = useRouter();
  const [drawer, setDrawer] = useState<DrawerState>(null);
  const [expandedRoom, setExpandedRoom] = useState<string | null>(null);
  const [assigning, setAssigning] = useState(false);
  const [assignMessage, setAssignMessage] = useState<string | null>(null);

  const totalAssigned = initial.rooms.reduce((sum, r) => sum + r.occupancy, 0);
  const totalCapacity = initial.rooms.reduce((sum, r) => sum + (r.capacity ?? 0), 0);

  const refresh = () => {
    setDrawer(null);
    router.refresh();
  };

  const handleAssignWaiting = async () => {
    if (assigning) return;
    setAssigning(true);
    setAssignMessage(null);
    try {
      const result = await assignWaitingPlayers(slug);
      if (!result.ok) {
        setAssigning(false);
        setAssignMessage(result.message);
        return;
      }
      setAssigning(false);
      setAssignMessage(
        result.data.assigned > 0
          ? `Assigned ${result.data.assigned} player${result.data.assigned === 1 ? "" : "s"}.`
          : "No open seats right now.",
      );
      router.refresh();
    } catch {
      setAssigning(false);
      setAssignMessage("Something went wrong. Please try again.");
    }
  };

  return (
    <main className="rc-admin-page">
      <header className="rc-admin-header">
        <h1 className="rc-admin-title">ROOMS</h1>
        <button type="button" className="rc-admin-add-room" onClick={() => setDrawer({ mode: "create" })}>
          + ADD ROOM
        </button>
      </header>

      <section className="rc-admin-metrics rc-admin-metrics--compact">
        <div className="rc-admin-metric">
          <span className="rc-admin-metric-value rc-numeric">{totalAssigned}</span>
          <span className="rc-admin-metric-label">ASSIGNED</span>
        </div>
        <div className="rc-admin-metric rc-admin-metric--warn">
          <span className="rc-admin-metric-value rc-numeric">{initial.waiting.length}</span>
          <span className="rc-admin-metric-label">WAITING</span>
        </div>
        <div className="rc-admin-metric">
          <span className="rc-admin-metric-value rc-numeric">{totalCapacity}</span>
          <span className="rc-admin-metric-label">TOTAL CAPACITY</span>
        </div>
      </section>

      <div className="rc-admin-room-list">
        {initial.rooms.map((room) => {
          const status = roomStatusLabel(room);
          return (
            <div key={room.id} className="rc-admin-room-card">
              <div className="rc-admin-room-card-top">
                <span className="rc-admin-room-dot" aria-hidden="true" />
                <span className="rc-admin-room-card-label rc-numeric">{room.label}</span>
                <span className="rc-admin-room-card-count rc-numeric">
                  {room.occupancy} / {room.capacity ?? "—"}
                </span>
                {status ? <span className={`rc-admin-status-pill rc-admin-tone-${status === "FULL" ? "accent" : "warn"}`}>{status}</span> : null}
              </div>
              <div className="rc-admin-room-card-meta">
                {whatsappBadge(room)}
                <span className="rc-admin-room-coordinator">
                  {room.coordinator ? `Coordinator: ${room.coordinator.name}` : ""}
                </span>
              </div>
              <div className="rc-admin-room-card-actions">
                <button
                  type="button"
                  className="rc-admin-view-players"
                  onClick={() => setExpandedRoom(expandedRoom === room.id ? null : room.id)}
                >
                  <svg viewBox="0 0 16 14" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
                    <circle cx="5.5" cy="4" r="2.6" />
                    <path d="M1 13c.6-3.4 2.2-5 4.5-5s3.9 1.6 4.5 5" />
                    <circle cx="11.5" cy="4.8" r="2" />
                    <path d="M11 8.3c1.8.2 3 1.6 3.5 4.2" />
                  </svg>
                  VIEW PLAYERS
                </button>
                {room.capacity === null || !room.whatsappGroupUrl ? (
                  <button type="button" className="rc-admin-configure" onClick={() => setDrawer({ mode: "edit", room })}>
                    CONFIGURE
                  </button>
                ) : (
                  <button type="button" className="rc-admin-room-more" onClick={() => setDrawer({ mode: "edit", room })} aria-label="Edit room">
                    •••
                  </button>
                )}
              </div>
              {expandedRoom === room.id ? (
                <MembersPanel roomId={room.id} onClose={() => setExpandedRoom(null)} />
              ) : null}
            </div>
          );
        })}
        {initial.rooms.length === 0 ? <p className="rc-admin-empty">No rooms yet — add one to get started.</p> : null}
      </div>

      <section className="rc-admin-card rc-admin-waiting">
        <div className="rc-admin-card-head">
          <h2 className="rc-admin-card-title rc-admin-tone-warn-text">
            WAITING FOR ROOM <span className="rc-numeric">{initial.waiting.length}</span>
          </h2>
        </div>
        {initial.waiting.length > 0 ? (
          <>
            <ul className="rc-admin-waiting-list">
              {initial.waiting.map((w) => (
                <li key={w.alias} className="rc-admin-waiting-row">
                  <PlayerAvatar alias={w.alias} size={1.75} />
                  <div className="rc-admin-waiting-info">
                    <span className="rc-numeric">{w.alias}</span>
                    <span className="rc-admin-waiting-meta">
                      #{String(w.playerNumber).padStart(3, "0")} · Checked in{" "}
                      {new Date(w.checkedInAt).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
            <button type="button" className="rc-admin-assign-waiting" onClick={handleAssignWaiting} disabled={assigning}>
              <svg viewBox="0 0 18 14" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
                <circle cx="6.5" cy="4" r="2.8" />
                <path d="M1 13c.6-3.8 2.5-5.6 5.5-5.6s4.9 1.8 5.5 5.6" />
                <path d="M12 3.5l1.5 1.5L17 1.5" />
              </svg>
              {assigning ? "ASSIGNING…" : "ASSIGN WAITING PLAYERS"}
            </button>
            {assignMessage ? <p className="rc-admin-assign-message">{assignMessage}</p> : null}
          </>
        ) : (
          <p className="rc-admin-empty">Nobody is waiting right now.</p>
        )}
      </section>

      <RoomDrawer slug={slug} state={drawer} onClose={() => setDrawer(null)} onSaved={refresh} />
    </main>
  );
}
