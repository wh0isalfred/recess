"use client";

import { useState } from "react";
import Image from "next/image";
import { useRouter, useSearchParams } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { Button } from "@/components/ui/Button";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { saveDraft, useDraftField } from "@/features/registration/draft";
import { validateAlias } from "@/features/registration/validation";

function ControllerIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="size-5">
      <rect x="2" y="7" width="16" height="9" rx="4" />
      <path d="M6.5 10v3M5 11.5h3M14.5 10.5h.01M12.5 12h.01" />
    </svg>
  );
}

/**
 * Errors register_player() can raise that are about the alias specifically
 * — mirrors the codes in features/registration/actions.ts's FRIENDLY map.
 * `alias_taken` can only be discovered at final submission (there is no
 * separate availability-check RPC — see delivery report), so WhatsAppStep
 * routes back here with the code in the URL rather than showing a
 * confusing "alias taken" message on a screen with no alias field.
 */
const ALIAS_SERVER_ERRORS: Record<string, string> = {
  alias_taken: "That name is already taken — try another.",
  invalid_alias: "2-24 letters, numbers, dots, underscores or hyphens.",
};

/**
 * V2 Screen 04 — Registration / Alias. Step 2 of 3.
 *
 * Format validation runs against the same regex register_player() enforces
 * (validateAlias, unchanged) and shows inline as soon as there's something
 * to say about it — never invented rules, never held back for submission.
 * True availability can only be known at submission (no separate check
 * exists), which is why a returning alias_taken error lands back here via
 * the `error` query param rather than being silently unrepresentable.
 */
export function AliasStep() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [alias, setAlias] = useDraftField("alias");
  const initialErrorCode = searchParams.get("error");
  const [touched, setTouched] = useState(Boolean(initialErrorCode));
  const [serverError, setServerError] = useState<string | null>(
    initialErrorCode && ALIAS_SERVER_ERRORS[initialErrorCode] ? ALIAS_SERVER_ERRORS[initialErrorCode] : null,
  );

  const trimmed = alias.trim();
  const formatError = touched ? validateAlias(alias) : null;
  const error = serverError ?? formatError;
  const preview = trimmed.toUpperCase();
  const ready = trimmed.length > 0 && validateAlias(alias) === null;

  const back = () => {
    saveDraft({ alias });
    router.push("/register");
  };

  const next = () => {
    setTouched(true);
    if (validateAlias(alias) !== null) return;
    saveDraft({ alias });
    router.push("/register/whatsapp");
  };

  return (
    <RegistrationShell step={2} onBack={back}>
      <h1 className="rc-reg-prompt">Your player name?</h1>
      <p className="rc-reg-subcopy">This is what everyone will see.</p>

      <div className="rc-reg-field">
        <Field
          id="player-alias"
          label="Player name"
          name="alias"
          autoFocus
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="next"
          placeholder="Enter a player name"
          prefix={<ControllerIcon />}
          hint={error ? undefined : "2-24 letters, numbers, dots, underscores or hyphens."}
          error={error ?? undefined}
          value={alias}
          onChange={(e) => {
            setAlias(e.target.value);
            setServerError(null);
          }}
          onBlur={() => setTouched(true)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && ready) next();
          }}
        />
      </div>

      {trimmed.length > 0 ? (
        <p className="rc-reg-preview" aria-live="polite">
          Player: <span className="rc-numeric">{preview}</span>
        </p>
      ) : null}

      <div className="rc-reg-illustration">
        <Image
          src="/brand/v2/onboarding-alias.webp"
          alt=""
          aria-hidden="true"
          width={423}
          height={280}
          priority
          className="rc-reg-illustration-art"
        />
      </div>

      <div className="rc-reg-foot">
        <Button variant="poster" size="lg" arrow disabled={!ready} onClick={next}>
          Continue
        </Button>
      </div>
    </RegistrationShell>
  );
}
