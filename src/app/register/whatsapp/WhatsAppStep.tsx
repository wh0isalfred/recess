"use client";

import { useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { PosterLine } from "@/components/brand/RecessWordmark";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { clearDraft, readDraft, saveDraft, useDraftField } from "@/features/registration/draft";
import { markPassFresh } from "@/features/pass/fresh";
import { COUNTRIES, findCountry } from "@/features/registration/countries";
import { validatePhone } from "@/features/registration/validation";
import { submitRegistration } from "@/features/registration/actions";

/**
 * Screen 05 — Registration / WhatsApp. Step 3 of 3.
 *
 * CLAIM MY SPOT is the transaction boundary: everything before this screen
 * is a local draft (src/features/registration/draft.ts), and this button is
 * the one place that calls the database. See submitRegistration() for what
 * "real" means here — an anonymous session, then register_player().
 */
export function WhatsAppStep() {
  const router = useRouter();
  const [phone, setPhone] = useDraftField("phone");
  const [country, setCountry] = useDraftField("country");
  const [consent, setConsent] = useDraftField("consent");

  // Submission is the one thing this screen does that the other two don't,
  // so its state lives here rather than growing the draft hook further.
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [touched, setTouched] = useState(false);

  const phoneError = touched ? validatePhone(phone, country) : null;
  const canSubmit = phone.trim().length > 0 && consent && !submitting;

  const back = () => {
    saveDraft({ phone, country, consent });
    router.push("/register/alias");
  };

  const claim = async () => {
    setTouched(true);
    setFormError(null);

    const localPhoneError = validatePhone(phone, country);
    if (localPhoneError) {
      // Already visible under the field itself via `phoneError` — a second
      // copy in the form-level slot would just repeat it.
      return;
    }
    if (!consent) {
      return;
    }

    // Guards the accidental-double-click case at the UI layer; the row lock
    // inside register_player() is what actually guarantees no duplicate,
    // this just avoids firing the request twice for no reason.
    if (submitting) return;
    setSubmitting(true);
    setFormError(null);

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
        setSubmitting(false);
        setFormError(result.message);
        return;
      }

      clearDraft();
      markPassFresh();
      router.push("/pass");
    } catch {
      // The server action itself threw rather than returning {ok:false} —
      // without this, a thrown promise leaves CLAIM MY SPOT stuck disabled
      // forever with no error shown and no way to retry.
      setSubmitting(false);
      setFormError("Something went wrong. Please try again.");
    }
  };

  return (
    <RegistrationShell step={3}>
      <Image
        src="/brand/rook-pink.webp"
        alt=""
        aria-hidden="true"
        width={640}
        height={665}
        className="rc-reg-rook"
        priority
      />

      <h1 className="rc-reg-heading">
        <PosterLine text="LAST THING." ratio={9.4} />
      </h1>

      <div className="rc-reg-field rc-reg-field--phone">
        <Field
          id="player-phone"
          label="WhatsApp number"
          name="phone"
          type="tel"
          inputMode="tel"
          autoComplete="tel-national"
          enterKeyHint="done"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          error={phoneError ?? undefined}
          placeholder={findCountry(country).nsnLength === 10 ? "801 234 5678" : undefined}
          prefix={
            <label className="rc-reg-country">
              <span className="sr-only">Country</span>
              <span aria-hidden="true">+{findCountry(country).dialCode}</span>
              <select
                value={country}
                onChange={(e) => setCountry(e.target.value)}
                aria-label="Country calling code"
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

      <p className="rc-reg-copy rc-reg-copy--tight">
        We&rsquo;ll only use this for RECESS updates
        <br />
        and the event group.
      </p>

      <label className="rc-reg-consent">
        <input
          type="checkbox"
          checked={consent}
          onChange={(e) => setConsent(e.target.checked)}
        />
        <span className="rc-reg-consent-box" aria-hidden="true">
          <svg viewBox="0 0 14 11" fill="none" stroke="currentColor" strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round">
            <path d="M1 5.5 5 9.5 13 1.5" />
          </svg>
        </span>
        <span>
          I agree to receive updates about
          <br />
          RECESS.
        </span>
      </label>

      {formError ? (
        <p className="rc-reg-form-error" role="alert">
          <span aria-hidden="true">✕</span> {formError}
        </p>
      ) : null}

      <div className="rc-reg-foot rc-reg-foot--split">
        <button type="button" className="rc-reg-back" onClick={back} disabled={submitting}>
          <span aria-hidden="true">←</span> BACK
        </button>
        <button
          type="button"
          className="rc-reg-next"
          disabled={!canSubmit}
          aria-busy={submitting || undefined}
          onClick={claim}
        >
          {submitting ? "CLAIMING…" : (
            <>CLAIM MY SPOT <span aria-hidden="true">→</span></>
          )}
        </button>
      </div>
    </RegistrationShell>
  );
}
