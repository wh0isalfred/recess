"use client";

import { useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { Button } from "@/components/ui/Button";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { RegistrationComplete } from "@/features/registration/RegistrationComplete";
import { clearDraft, readDraft, saveDraft, useDraftField } from "@/features/registration/draft";
import { COUNTRIES, findCountry } from "@/features/registration/countries";
import { validatePhone } from "@/features/registration/validation";
import { submitRegistration } from "@/features/registration/actions";

function LockIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="size-4">
      <rect x="3" y="7" width="10" height="7" rx="1.5" />
      <path d="M5 7V4.5a3 3 0 0 1 6 0V7" />
    </svg>
  );
}

/**
 * Alias-related codes get routed back to the alias screen (see that file's
 * own comment) rather than shown here, where there's no alias field for the
 * error to sit under.
 */
const ALIAS_CODES = new Set(["alias_taken", "invalid_alias"]);

/**
 * V2 Screen 05 — Registration / WhatsApp. Step 3 of 3.
 *
 * CLAIM MY SPOT is still the one real transaction boundary — everything
 * before this is a local draft (draft.ts), and submitRegistration() below is
 * unchanged: same anonymous-session bootstrap, same register_player() call,
 * same RegisterResult contract. What's new is what happens after a success
 * response: instead of navigating immediately, `phase` flips to "success"
 * and RegistrationComplete renders the hold-then-transition the brief asks
 * for; navigation to /pass happens once that component's timer calls back.
 */
export function WhatsAppStep() {
  const router = useRouter();
  const [phone, setPhone] = useDraftField("phone");
  const [country, setCountry] = useDraftField("country");
  const [consent, setConsent] = useDraftField("consent");

  const [phase, setPhase] = useState<"form" | "submitting" | "success">("form");
  const [formError, setFormError] = useState<string | null>(null);
  const [touched, setTouched] = useState(false);

  const phoneError = touched ? validatePhone(phone, country) : null;
  const canSubmit = phone.trim().length > 0 && consent && phase === "form";

  const back = () => {
    saveDraft({ phone, country, consent });
    router.push("/register/alias");
  };

  const claim = async () => {
    setTouched(true);
    setFormError(null);

    if (validatePhone(phone, country)) return;
    if (!consent) return;
    if (phase !== "form") return;

    setPhase("submitting");

    const draft = readDraft();
    try {
      const result = await submitRegistration({
        name: draft.name,
        alias: draft.alias,
        phone,
        countryIso2: country,
        consent,
      });

      if (!result.ok) {
        if (ALIAS_CODES.has(result.code)) {
          saveDraft({ phone, country, consent });
          router.push(`/register/alias?error=${result.code}`);
          return;
        }
        setPhase("form");
        setFormError(result.message);
        return;
      }

      // The draft's job ends here; the real registration exists now. See
      // draft.ts's own comment for why this matters for a second, unrelated
      // registration in the same browser later.
      clearDraft();
      setPhase("success");
    } catch {
      // Thrown rather than returned {ok:false} — without this, CLAIM MY
      // SPOT is stuck disabled forever with no error and no retry.
      setPhase("form");
      setFormError("Something went wrong. Please try again.");
    }
  };

  if (phase === "success") {
    return (
      <RegistrationShell step={3} hideChrome>
        <RegistrationComplete onDone={() => router.push("/pass")} />
      </RegistrationShell>
    );
  }

  const submitting = phase === "submitting";

  return (
    <RegistrationShell step={3} onBack={back}>
      <h1 className="rc-reg-prompt">Your WhatsApp number?</h1>
      <p className="rc-reg-subcopy">We&rsquo;ll use this for event updates.</p>

      <div className="rc-reg-field">
        <Field
          id="player-phone"
          label="WhatsApp number"
          name="phone"
          type="tel"
          inputMode="tel"
          autoFocus
          autoComplete="tel-national"
          enterKeyHint="done"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          onBlur={() => setTouched(true)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && canSubmit) claim();
          }}
          error={phoneError ?? undefined}
          placeholder={findCountry(country).nsnLength === 10 ? "801 234 5678" : "Enter your number"}
          prefix={
            <label className="rc-reg-country">
              <span className="sr-only">Country</span>
              <span aria-hidden="true">+{findCountry(country).dialCode}</span>
              <select
                value={country}
                onChange={(e) => setCountry(e.target.value)}
                aria-label="Country calling code"
                disabled={submitting}
              >
                {COUNTRIES.map((c) => (
                  <option key={c.iso2} value={c.iso2}>
                    {c.name} (+{c.dialCode})
                  </option>
                ))}
              </select>
              <svg className="rc-reg-country-chevron" viewBox="0 0 12 8" fill="none"
                stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
                aria-hidden="true">
                <path d="M1 1.5 6 6.5 11 1.5" />
              </svg>
            </label>
          }
        />
      </div>

      <p className="rc-reg-assurance">
        <LockIcon /> No spam. No nonsense.
      </p>

      <label className="rc-reg-consent">
        <input
          type="checkbox"
          checked={consent}
          disabled={submitting}
          onChange={(e) => setConsent(e.target.checked)}
        />
        <span className="rc-reg-consent-box" aria-hidden="true">
          <svg viewBox="0 0 14 11" fill="none" stroke="currentColor" strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round">
            <path d="M1 5.5 5 9.5 13 1.5" />
          </svg>
        </span>
        <span>I agree to receive updates about RECESS.</span>
      </label>

      {formError ? (
        <p className="rc-reg-form-error" role="alert">
          <span aria-hidden="true">✕</span> {formError}
        </p>
      ) : null}

      <div className="rc-reg-illustration">
        <Image
          src="/brand/v2/onboarding-whatsapp.webp"
          alt=""
          aria-hidden="true"
          width={422}
          height={258}
          priority
          className="rc-reg-illustration-art"
        />
      </div>

      <div className="rc-reg-foot">
        <Button
          variant="poster"
          size="lg"
          arrow
          disabled={!canSubmit}
          loading={submitting}
          loadingLabel="Claiming your spot"
          onClick={claim}
        >
          Claim my spot
        </Button>
      </div>
    </RegistrationShell>
  );
}
