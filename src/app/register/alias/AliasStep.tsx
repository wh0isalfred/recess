"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { PosterLine } from "@/components/brand/RecessWordmark";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { saveDraft, useDraftField } from "@/features/registration/draft";

/**
 * Screen 04 — Registration / Alias. Step 2 of 3.
 *
 * The preview shows the alias the way the rest of RECESS will display it —
 * upper case — while the field keeps exactly what was typed. Uppercasing is a
 * presentation decision, so it does not touch the stored value.
 *
 * Visual pass: no player record, no uniqueness check. That is the CONNECT
 * step, and it is a server-side check when it comes.
 */
export function AliasStep() {
  const router = useRouter();
  const [alias, setAlias] = useDraftField("alias");

  const trimmed = alias.trim();
  const preview = trimmed.toUpperCase();

  const back = () => {
    saveDraft({ alias });
    router.push("/register");
  };

  const next = () => {
    saveDraft({ alias });
    router.push("/register/whatsapp");
  };

  return (
    <RegistrationShell step={2}>
      <Image
        src="/brand/knight-orange.webp"
        alt=""
        aria-hidden="true"
        width={520}
        height={661}
        className="rc-reg-knight"
        priority
      />

      <h1 className="rc-reg-heading rc-reg-heading--stacked">
        <span className="sr-only">What do we call you?</span>
        <PosterLine text="WHAT DO WE" ratio={7.1} className="rc-reg-heading-a" />
        <PosterLine text="CALL YOU?" ratio={5.77} className="rc-reg-heading-b" />
      </h1>

      <p className="rc-reg-copy">
        Your RECESS name.
        <br />
        This is what everyone else sees.
      </p>

      <div className="rc-reg-field rc-reg-field--bare">
        <Field
          id="player-alias"
          label="Your RECESS name"
          name="alias"
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="next"
          value={alias}
          onChange={(e) => setAlias(e.target.value)}
        />
      </div>

      <div className="rc-reg-preview">
        <p className="rc-reg-preview-label">Player preview</p>
        <p className="rc-reg-preview-alias" aria-live="polite">
          {preview || "\u00A0"}
        </p>
      </div>

      <div className="rc-reg-foot rc-reg-foot--split">
        <button type="button" className="rc-reg-back" onClick={back}>
          <span aria-hidden="true">←</span> BACK
        </button>
        <button type="button" className="rc-reg-next" disabled={trimmed.length === 0} onClick={next}>
          THAT&rsquo;S ME <span aria-hidden="true">→</span>
        </button>
      </div>
    </RegistrationShell>
  );
}
