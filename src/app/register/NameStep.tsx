"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { Button } from "@/components/ui/Button";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { saveDraft, useDraftField } from "@/features/registration/draft";
import { validateName } from "@/features/registration/validation";

function PersonIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="size-5">
      <circle cx="10" cy="6.5" r="3.5" />
      <path d="M3 17c0-3.5 3-6 7-6s7 2.5 7 6" />
    </svg>
  );
}

/**
 * V2 Screen 03 — Registration / Name. Step 1 of 3.
 *
 * One question, one field, one obvious action — no poster lettering, no
 * illustration copy beyond the supplied ticket art. The name still lives in
 * the session draft only (src/features/registration/draft.ts, unchanged);
 * nothing here writes to the database.
 */
export function NameStep() {
  const router = useRouter();
  const [name, setName] = useDraftField("name");

  const ready = validateName(name) === null;

  const next = () => {
    saveDraft({ name });
    router.push("/register/alias");
  };

  return (
    <RegistrationShell step={1} onBack={() => router.push("/")}>
      <h1 className="rc-reg-prompt">What&rsquo;s your name?</h1>

      <div className="rc-reg-field">
        <Field
          id="player-name"
          label="Your name"
          name="name"
          autoFocus
          autoComplete="given-name"
          autoCapitalize="words"
          enterKeyHint="next"
          placeholder="Enter your name"
          prefix={<PersonIcon />}
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && ready) next();
          }}
        />
      </div>

      <div className="rc-reg-illustration">
        <Image
          src="/brand/v2/onboarding-name.webp"
          alt=""
          aria-hidden="true"
          width={422}
          height={332}
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
