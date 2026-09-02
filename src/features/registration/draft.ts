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
};

const EMPTY: RegistrationDraft = { name: "", alias: "" };

export function readDraft(): RegistrationDraft {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return EMPTY;
    const parsed = JSON.parse(raw) as Partial<RegistrationDraft>;
    return {
      name: typeof parsed.name === "string" ? parsed.name : "",
      alias: typeof parsed.alias === "string" ? parsed.alias : "",
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

const NO_SUBSCRIPTION = () => () => {};

/**
 * A draft field wired to an input.
 *
 * The server has no session storage, so it renders empty and the stored value
 * arrives on the client — `useSyncExternalStore` does that handover without a
 * hydration mismatch and without setting state from an effect. Once the person
 * types, what they typed wins.
 */
export function useDraftField(field: keyof RegistrationDraft) {
  const stored = useSyncExternalStore(
    NO_SUBSCRIPTION,
    () => readDraft()[field],
    () => "",
  );
  const [typed, setTyped] = useState<string | null>(null);
  return [typed ?? stored, setTyped] as const;
}
