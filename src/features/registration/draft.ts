"use client";

import { useState, useSyncExternalStore } from "react";

/**
 * The in-progress registration, held for this browser session only.
 *
 * Purely local: it exists so stepping back and forward through the three
 * registration screens does not lose what has been typed. No player record,
 * no server call, nothing that outlives the tab. The real write happens once,
 * at the end of the flow, in the CONNECT step.
 */
const KEY = "recess.registration";

export type RegistrationDraft = {
  name: string;
  alias: string;
  /** Local part only, as typed — never includes the country code. */
  phone: string;
  /** ISO 3166-1 alpha-2, e.g. "NG". Drives both the dial code and the shape hint. */
  country: string;
  consent: boolean;
};

const EMPTY: RegistrationDraft = { name: "", alias: "", phone: "", country: "NG", consent: false };

export function readDraft(): RegistrationDraft {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return EMPTY;
    const parsed = JSON.parse(raw) as Partial<RegistrationDraft>;
    return {
      name: typeof parsed.name === "string" ? parsed.name : "",
      alias: typeof parsed.alias === "string" ? parsed.alias : "",
      phone: typeof parsed.phone === "string" ? parsed.phone : "",
      country: typeof parsed.country === "string" ? parsed.country : EMPTY.country,
      consent: typeof parsed.consent === "boolean" ? parsed.consent : false,
    };
  } catch {
    return EMPTY;
  }
}

export function saveDraft(patch: Partial<RegistrationDraft>) {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.setItem(KEY, JSON.stringify({ ...readDraft(), ...patch }));
  } catch {
    /* private mode, quota — the flow still works, it just forgets */
  }
}

/**
 * Called once, after a successful register_player() call. The draft's job
 * ends where the real registration begins — nothing here is needed again,
 * and leaving it would let a stale name/alias resurface if the same browser
 * ever starts a second, unrelated registration.
 */
export function clearDraft() {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    /* nothing to clean up if this throws */
  }
}

const NO_SUBSCRIPTION = () => () => {};

/**
 * A draft field wired to an input.
 *
 * The server has no session storage, so it renders empty and the stored value
 * arrives on the client — `useSyncExternalStore` does that handover without a
 * hydration mismatch and without setting state from an effect. Once the person
 * types, what they typed wins.
 */
export function useDraftField<K extends keyof RegistrationDraft>(field: K) {
  const stored = useSyncExternalStore(
    NO_SUBSCRIPTION,
    () => readDraft()[field],
    () => EMPTY[field],
  );
  const [typed, setTyped] = useState<RegistrationDraft[K] | null>(null);
  return [typed ?? stored, setTyped] as const;
}
