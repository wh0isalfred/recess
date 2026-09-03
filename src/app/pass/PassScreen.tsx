"use client";

import { useEffect, useSyncExternalStore } from "react";
import { Surface } from "@/components/ui/Surface";
import { Ticket } from "@/components/ui/Ticket";
import { PlayMark } from "@/components/brand/PlayMark";
import { PosterLine } from "@/components/brand/RecessWordmark";
import type { RegistrationState } from "@/features/registration/types";
import {
  downloadEventIcs,
  formatEventDate,
  formatEventTime,
  formatPlayerNumber,
  isValidWhatsAppGroupUrl,
} from "@/features/registration/calendar";
import type { PlayerState } from "@/features/pass/types";
import { clearPassFreshFlag, hasPassFreshFlag } from "@/features/pass/fresh";
import { EventPassScreen } from "./EventPassScreen";
import { CheckInScreen } from "./CheckInScreen";

/**
 * The Screen 06 celebration and its waitlisted sibling, unchanged from
 * before this task — only the props feeding them now come from
 * get_player_state() instead of get_my_registration(), adapted below.
 */
function Confetti() {
  const pieces = [
    { x: "10%", y: "6%", r: -18, c: "var(--pink-lift)" },
    { x: "82%", y: "4%", r: 24, c: "var(--amber)" },
    { x: "92%", y: "16%", r: -10, c: "var(--pink-lift)" },
    { x: "6%", y: "22%", r: 30, c: "var(--amber)" },
    { x: "88%", y: "30%", r: -22, c: "var(--pink-lift)" },
    { x: "14%", y: "34%", r: 14, c: "var(--amber)" },
  ];
  return (
    <div className="rc-pass-confetti" aria-hidden="true">
      {pieces.map((p, i) => (
        <span key={i} style={{ left: p.x, top: p.y, background: p.c, transform: `rotate(${p.r}deg)` }} />
      ))}
    </div>
  );
}

function Confirmed({ registration }: { registration: RegistrationState }) {
  const hasGroup = isValidWhatsAppGroupUrl(registration.whatsappGroupUrl);
  return (
    <>
      <PlayMark className="rc-pass-mark" />
      <h1 className="rc-pass-heading">
        <PosterLine text="YOU'RE IN." ratio={6.6} />
      </h1>
      <p className="rc-pass-alias rc-numeric">{registration.alias}</p>
      <div className="rc-pass-ticket rc-stamp">
        <Ticket label="Player number" value={formatPlayerNumber(registration.playerNumber)} />
      </div>
      <div className="rc-pass-schedule">
        <p>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
            <rect x="2" y="3" width="12" height="11" rx="1.5" />
            <path d="M2 6.5h12M5.5 1.5v3M10.5 1.5v3" />
          </svg>
          {formatEventDate(registration.startsAt, registration.timezone)}
        </p>
        <p>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
            <circle cx="8" cy="8" r="6.3" />
            <path d="M8 4.5V8l3 1.8" />
          </svg>
          {formatEventTime(registration.startsAt, registration.timezone)} {registration.timezoneLabel}
        </p>
      </div>
      {hasGroup ? (
        <a href={registration.whatsappGroupUrl!} className="rc-pass-whatsapp" target="_blank" rel="noreferrer">
          JOIN WHATSAPP GROUP <span aria-hidden="true">→</span>
        </a>
      ) : (
        <p className="rc-pass-whatsapp rc-pass-whatsapp--pending" aria-live="polite">
          WhatsApp group link coming soon
        </p>
      )}
      <button type="button" className="rc-pass-calendar" onClick={() => downloadEventIcs(registration)}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
          <rect x="2" y="3" width="12" height="11" rx="1.5" />
          <path d="M2 6.5h12M5.5 1.5v3M10.5 1.5v3" />
        </svg>
        ADD TO CALENDAR
      </button>
    </>
  );
}

function Waitlisted({ registration }: { registration: RegistrationState }) {
  return (
    <>
      <PlayMark className="rc-pass-mark" />
      <h1 className="rc-pass-heading">
        <PosterLine text="YOU'RE ON THE LIST." ratio={11.5} />
      </h1>
      <p className="rc-pass-alias rc-numeric">{registration.alias}</p>
      <p className="rc-pass-waitlist-copy">
        RECESS is full right now. You&rsquo;re {formatPlayerNumber(registration.playerNumber)} on the waitlist for{" "}
        {formatEventDate(registration.startsAt, registration.timezone)} — we&rsquo;ll reach out on WhatsApp if a
        spot opens up.
      </p>
    </>
  );
}

/**
 * A checked-in player who refreshes /pass before Screen 09 exists must land
 * somewhere true, not somewhere blank or somewhere pretending to be a
 * finished screen. Plain, in the system's own type and colour — the same
 * treatment WAITLISTED already got on Screen 06 before it had a reference.
 */
function MinimalFallback({ state }: { state: PlayerState }) {
  const copy: Record<string, string> = {
    CHECKED_IN_WAITING: "You're checked in. We'll place you in a room shortly.",
    ROOM_ASSIGNED: `You're checked in and in ${state.room?.label ?? "a room"}.`,
    MISSED_CHECK_IN: "Check-in has moved on without you — find a coordinator at the venue.",
    EVENT_CANCELLED: "This RECESS has been cancelled.",
    CANCELLED: "This registration was cancelled.",
    LATE_ARRIVAL: "You're checked in. Find a coordinator to join a room.",
    LIVE_ROUND: "RECESS is live right now.",
    BETWEEN_GAMES: "Between games right now.",
    PAUSED: "Play is paused right now.",
    RESULTS: "RECESS has wrapped — results are in.",
  };
  return (
    <>
      <PlayMark className="rc-pass-mark" />
      <p className="rc-pass-alias rc-numeric">{state.player.alias}</p>
      <p className="rc-pass-waitlist-copy">{copy[state.view] ?? "Check back soon."}</p>
    </>
  );
}

function toRegistrationState(state: PlayerState): RegistrationState {
  return {
    registrationId: `${state.event.slug}-${state.player.number}`,
    playerNumber: state.player.number,
    alias: state.player.alias,
    status: state.player.registrationStatus,
    eventId: state.event.slug,
    eventSlug: state.event.slug,
    eventName: state.event.name,
    startsAt: state.event.startsAt,
    timezone: state.event.timezone,
    timezoneLabel: state.event.timezoneLabel,
    whatsappGroupUrl: state.event.whatsappGroupUrl,
  };
}

const NO_SUBSCRIPTION = () => () => {};

export function PassScreen({ state }: { state: PlayerState }) {
  // Hydration-safe read: the server always renders as if the flag is unset
  // (sessionStorage doesn't exist there), and the client's real value —
  // possibly different — arrives via useSyncExternalStore's dedicated path
  // for exactly this without a mismatch warning. The flag is cleared
  // separately, in a plain effect below, never inside this getSnapshot,
  // which React may call more than once per render and must stay pure.
  const fresh = useSyncExternalStore(NO_SUBSCRIPTION, hasPassFreshFlag, () => false);

  useEffect(() => {
    if (fresh) clearPassFreshFlag();
  }, [fresh]);

  if (state.view === "WAITLISTED") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-pass">
        <div className="rc-pass-stage">
          <Waitlisted registration={toRegistrationState(state)} />
        </div>
      </Surface>
    );
  }

  if (state.view === "PASS_COUNTDOWN") {
    // useSyncExternalStore resolves the real client value synchronously
    // during hydration, before paint — so a genuinely fresh registration
    // does not flash Screen 07 before settling on the celebration.
    if (!fresh) {
      return (
        <Surface as="main" ground="paper" grain="low" className="rc-evp">
          <EventPassScreen state={state} />
        </Surface>
      );
    }
    return (
      <Surface as="main" ground="night" grain="low" className="rc-pass">
        <Confetti />
        <div className="rc-pass-stage">
          <Confirmed registration={toRegistrationState(state)} />
        </div>
      </Surface>
    );
  }

  if (state.view === "CHECK_IN_OPEN") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-chk">
        <CheckInScreen state={state} />
      </Surface>
    );
  }

  return (
    <Surface as="main" ground="night" grain="low" className="rc-pass">
      <div className="rc-pass-stage">
        <MinimalFallback state={state} />
      </div>
    </Surface>
  );
}
