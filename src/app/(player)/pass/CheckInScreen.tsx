"use client";

import Image from "next/image";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { RecessWordmark, BrushGesture } from "@/components/brand/RecessWordmark";
import type { PlayerState } from "@/features/pass/types";
import { checkIn } from "@/features/pass/actions";

function OverflowMenu() {
  return (
    <button type="button" className="rc-chk-overflow" aria-label="More options">
      <svg viewBox="0 0 20 6" fill="currentColor" aria-hidden="true">
        <circle cx="2.5" cy="3" r="2.2" />
        <circle cx="10" cy="3" r="2.2" />
        <circle cx="17.5" cy="3" r="2.2" />
      </svg>
    </button>
  );
}

/**
 * Reference 2, the check-in state. The die is the approved asset
 * (public/brand/die-pink.webp) — decorative, so it's aria-hidden.
 *
 * "Check in opens at 7:30 PM" versus "open now" is the one thing this
 * screen varies on its own: the route resolver (page.tsx) already only
 * renders this component once event.status = CHECK_IN, but the exact
 * checkin_opens_at/closes_at window is a separate, optional refinement on
 * top of that — a coordinator can flip the event to CHECK_IN status ahead
 * of the actual doors-open time. checkIn.available carries that second
 * fact, and the button and copy below follow it, per the brief's own
 * instruction to preserve the reference's copy-swap rather than fall back
 * to Screen 07 for that case.
 */
export function CheckInScreen({ state }: { state: PlayerState }) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const alreadyCheckedIn = !!state.player.checkedInAt;

  const opensAt = state.checkIn.opensAt
    ? new Intl.DateTimeFormat("en-US", {
        hour: "numeric",
        minute: "2-digit",
        hour12: true,
        timeZone: state.event.timezone,
      }).format(new Date(state.checkIn.opensAt))
    : null;

  const handleCheckIn = async () => {
    if (submitting || alreadyCheckedIn) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await checkIn();
      if (!result.ok) {
        setSubmitting(false);
        setError(result.message);
        return;
      }
      // The transaction succeeded — CHECKED_IN_WAITING/ROOM_ASSIGNED render as
      // a controlled, minimal fallback (see PassScreen); Screen 09's real
      // design is explicitly out of scope for this task.
      router.refresh();
    } catch {
      // The server action itself threw — a network drop, a cold-start
      // failure, anything short of check_in_player() returning a normal
      // {ok:false}. Without this, a thrown promise leaves the button stuck
      // on "CHECKING IN…" forever with no way for the player to retry.
      setSubmitting(false);
      setError("Something went wrong. Please try again.");
    }
  };

  return (
    <div className="rc-chk-stage">
      <header className="rc-chk-top">
        <span className="rc-chk-mark">
          <RecessWordmark />
          <BrushGesture className="rc-chk-gesture" />
          <span className="sr-only">RECESS</span>
        </span>
        <OverflowMenu />
      </header>

      <p className="rc-chk-eyebrow">IT&rsquo;S RECESS DAY!</p>
      <h1 className="rc-chk-heading">CHECK IN</h1>

      <p className="rc-chk-sub">
        {alreadyCheckedIn
          ? "You're checked in."
          : state.checkIn.available || !opensAt
            ? "Check-in is open."
            : `Check in opens at ${opensAt}`}
      </p>

      <div className="rc-chk-die">
        <Image src="/brand/old/die-pink.webp" alt="" aria-hidden="true" width={640} height={640} priority />
      </div>

      {error ? (
        <p className="rc-chk-error" role="alert">
          <span aria-hidden="true">✕</span> {error}
        </p>
      ) : null}

      <button
        type="button"
        className="rc-chk-cta"
        onClick={handleCheckIn}
        disabled={submitting || alreadyCheckedIn || !state.checkIn.available}
        aria-busy={submitting || undefined}
      >
        {alreadyCheckedIn ? "CHECKED IN" : submitting ? "CHECKING IN…" : (
          <>CHECK IN NOW <span aria-hidden="true">→</span></>
        )}
      </button>

      <p className="rc-chk-footer">
        <svg viewBox="0 0 14 16" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
          <rect x="2" y="7" width="10" height="7.5" rx="1.3" />
          <path d="M4.2 7V4.5a2.8 2.8 0 0 1 5.6 0V7" />
        </svg>
        ROOM REVEALED AFTER CHECK-IN
      </p>
    </div>
  );
}
