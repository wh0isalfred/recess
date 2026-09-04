"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { openCheckIn, openRegistration } from "@/features/admin/actions";
import type { AdminResult } from "@/features/admin/types";

type Action = "registration" | "checkin";

const LABEL: Record<Action, string> = { registration: "OPEN REGISTRATION", checkin: "OPEN CHECK-IN" };
const BUSY_LABEL: Record<Action, string> = { registration: "OPENING…", checkin: "OPENING…" };

/**
 * One button, two lifecycle transitions — both are the exact same shape:
 * a SECURITY DEFINER wrapper (admin_open_registration / admin_open_check_in,
 * migrations 0019/0018) resolves the event and enforces
 * require_event_admin() before calling the real transition_event() (0012).
 * This component only decides which wrapper to call; the state machine's
 * own preconditions — a registration window, at least one game, a
 * check-in window, at least one room — decide whether it can actually
 * succeed, not this component.
 */
export function LifecycleButton({ slug, action, disabled }: { slug: string; action: Action; disabled: boolean }) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleClick = async () => {
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const result: AdminResult<unknown> = action === "registration" ? await openRegistration(slug) : await openCheckIn(slug);
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
        {submitting ? BUSY_LABEL[action] : LABEL[action]}
      </button>
      {error ? <p className="rc-admin-error rc-admin-error--inline">{error}</p> : null}
    </div>
  );
}
