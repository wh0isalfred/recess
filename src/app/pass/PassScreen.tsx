"use client";

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

/**
 * The confirmed-attendance version of Screen 06. Reference 3 is authoritative
 * for this state only — see PassScreen below for the WAITLISTED branch,
 * which has no supplied reference.
 */
function Confetti() {
  // A handful of fixed shards, not a particle system — "restrained
  // celebration," matching the reference's static scatter rather than the
  // one non-user-triggered motion the system already spends on rc-stamp.
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
        <span
          key={i}
          style={{
            left: p.x,
            top: p.y,
            background: p.c,
            transform: `rotate(${p.r}deg)`,
          }}
        />
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

/**
 * WAITLISTED has no supplied reference — register_player() can produce it
 * (the event's capacity is a real, enforced number; see the migration), but
 * nobody has designed what it looks like yet. This is a plain, honest
 * fallback in the existing system's own type and colour, not a guess at art
 * direction. Flagged in the delivery report — a real Screen 06b reference
 * would replace this.
 */
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

export function PassScreen({ registration }: { registration: RegistrationState }) {
  const waitlisted = registration.status === "WAITLISTED";

  return (
    <Surface as="main" ground="night" grain="low" className="rc-pass">
      {waitlisted ? null : <Confetti />}
      <div className="rc-pass-stage">
        {waitlisted ? <Waitlisted registration={registration} /> : <Confirmed registration={registration} />}
      </div>
    </Surface>
  );
}
