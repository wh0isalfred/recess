"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { openCheckIn } from "@/features/admin/actions";

/**
 * Calls admin_open_check_in() (migration 0018), which resolves the event
 * server-side and calls the real transition_event() (0012) — the state
 * machine's own legality guards (a configured check-in window, at least one
 * room) decide whether this can actually succeed, not this component.
 */
export function OpenCheckInButton({ disabled }: { disabled: boolean }) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleClick = async () => {
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await openCheckIn();
      if (!result.ok) {
        setSubmitting(false);
        setError(result.message);
        return;
      }
      router.refresh();
    } catch {
      setSubmitting(false);
      setError("Something went wrong. Please try again.");
    }
  };

  if (disabled) return null;

  return (
    <div className="rc-admin-open-checkin">
      <button type="button" className="rc-admin-open-checkin-btn" onClick={handleClick} disabled={submitting}>
        <svg viewBox="0 0 14 16" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">
          <rect x="2" y="7" width="10" height="7.5" rx="1.3" />
          <path d="M4.2 7V4.5a2.8 2.8 0 0 1 5.6 0V7" />
        </svg>
        {submitting ? "OPENING…" : "OPEN CHECK-IN"}
      </button>
      {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
    </div>
  );
}
