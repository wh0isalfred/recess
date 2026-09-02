"use client";

import { useRouter } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { PawnMark } from "@/components/brand/PawnMark";
import { PosterLine } from "@/components/brand/RecessWordmark";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { saveDraft, useDraftField } from "@/features/registration/draft";

/**
 * Screen 03 — Registration / Name. Step 1 of 3.
 *
 * Visual pass: the name lives in the session draft so stepping forward and
 * back does not lose it. No Supabase, no player record, no capacity check.
 */
export function NameStep() {
  const router = useRouter();
  const [name, setName] = useDraftField("name");

  const ready = name.trim().length > 0;

  const next = () => {
    saveDraft({ name });
    router.push("/register/alias");
  };

  return (
    <RegistrationShell step={1}>
      <h1 className="rc-reg-heading">
        <span className="sr-only">Let&rsquo;s get you in.</span>
        <PosterLine text={"LET\u2019S GET YOU IN."} />
      </h1>

      <div className="rc-reg-field">
        <Field
          id="player-name"
          label="What's your name?"
          name="name"
          autoComplete="given-name"
          autoCapitalize="words"
          enterKeyHint="next"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
      </div>

      <div className="rc-reg-foot">
        <PawnMark className="rc-reg-pawn" />
        <button type="button" className="rc-reg-next" disabled={!ready} onClick={next}>
          NEXT <span aria-hidden="true">→</span>
        </button>
      </div>
    </RegistrationShell>
  );
}
