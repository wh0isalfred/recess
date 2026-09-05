"use client";

import { useEffect } from "react";

/**
 * The post-submit transition: form clears, a checkmark draws in, "REGISTRATION
 * COMPLETE" holds briefly, then the caller is told to move on. This is
 * deliberately not a route — WhatsAppStep renders it in place of the form
 * once `register_player()` succeeds, then navigates to `/pass` itself once
 * `onDone` fires. `/pass` renders the calm Screen 07 directly; the one-time
 * "YOU'RE IN" celebration that used to run there (`markPassFresh()`, Screen
 * 06) is intentionally not triggered from here — this transition is now that
 * moment, and the brief is explicit: no additional confirmation screen after
 * this one. See the delivery report for the consequence that leaves for
 * `/pass`'s own fresh-flag screen, which is Pass's file, not touched here.
 *
 * `prefers-reduced-motion` drops the draw/scale-in animation (the mark just
 * appears) but keeps the hold duration — the pause is for reading the
 * confirmation, not decoration, so it doesn't shrink just because motion is
 * reduced.
 */
export function RegistrationComplete({ onDone }: { onDone: () => void }) {
  useEffect(() => {
    if (typeof navigator !== "undefined" && "vibrate" in navigator) {
      try {
        navigator.vibrate(12);
      } catch {
        /* not supported / not permitted — silent, this is a nicety */
      }
    }
    const t = setTimeout(onDone, 1600);
    return () => clearTimeout(t);
  }, [onDone]);

  return (
    <div className="rc-reg-complete" role="status" aria-live="polite">
      <svg
        className="rc-reg-complete-mark"
        viewBox="0 0 64 64"
        fill="none"
        aria-hidden="true"
      >
        <circle
          className="rc-reg-complete-ring"
          cx="32"
          cy="32"
          r="29"
          stroke="currentColor"
          strokeWidth="3"
        />
        <path
          className="rc-reg-complete-check"
          d="M19 33.5 27.5 42 46 21.5"
          stroke="currentColor"
          strokeWidth="4.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      <p className="rc-reg-complete-text">
        Registration
        <br />
        complete
      </p>
    </div>
  );
}
