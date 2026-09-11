"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

const SAFETY_REFRESH_MS = 25_000;

/**
 * The Gate B safety-refresh mechanism — deliberately not Realtime. Calls
 * router.refresh() (a fresh server render, re-running get_player_state())
 * on a conservative interval, plus immediately whenever the tab becomes
 * visible again or the browser regains a network connection. This is the
 * entire "keep a live-night screen from going stale" strategy for this
 * phase; full Realtime (broadcast a nudge, refetch on receipt) remains a
 * later phase's work, per the approved Gate A spec.
 *
 * Mounted once, by PassScreen, only while the player is in a state where
 * something could change without their own action (LIVE_ROUND and
 * friends) — never per individual screen component, so there is exactly
 * one interval and one set of listeners regardless of which live screen
 * is currently showing.
 */
export function LiveStateRefresher({ active }: { active: boolean }) {
  const router = useRouter();
  const inFlight = useRef(false);

  useEffect(() => {
    if (!active) return;

    const refresh = () => {
      if (document.hidden) return; // never poll a hidden tab
      if (inFlight.current) return; // never overlap two refreshes
      inFlight.current = true;
      router.refresh();
      // router.refresh() doesn't resolve a promise we can await here;
      // release the guard on the next tick, which is enough to prevent a
      // genuine double-fire from two near-simultaneous triggers (e.g. a
      // visibility change landing right on an interval tick).
      setTimeout(() => {
        inFlight.current = false;
      }, 500);
    };

    const interval = setInterval(refresh, SAFETY_REFRESH_MS);

    const onVisibility = () => {
      if (!document.hidden) refresh();
    };
    const onOnline = () => refresh();

    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("online", onOnline);

    return () => {
      clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("online", onOnline);
    };
  }, [active, router]);

  return null;
}
