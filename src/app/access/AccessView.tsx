"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { Field } from "@/components/ui/Field";
import { Button } from "@/components/ui/Button";
import { RegistrationShell } from "@/features/registration/RegistrationShell";
import { COUNTRIES, findCountry } from "@/features/registration/countries";
import { validatePhone, normalizeE164 } from "@/features/registration/validation";
import { createClient } from "@/lib/supabase/client";
import { recoverPlayerAccess } from "@/features/access/actions";

const RESEND_COOLDOWN_SECONDS = 30;

/**
 * /access — "Already in RECESS? Open your pass." Two screens, same
 * onboarding chrome as /register (RegistrationShell, total=2 here instead
 * of 3). Real Supabase phone OTP throughout: signInWithOtp() sends the
 * code, verifyOtp() is what actually proves phone ownership — RECESS
 * never invents its own OTP mechanism or trusts a client-supplied phone
 * as proof of anything. recover_player_access() runs only after that
 * verification succeeds, and derives the phone from the now-verified
 * server-side session itself.
 */
export function AccessView() {
  const router = useRouter();
  const supabase = useRef(createClient()).current;

  const [screen, setScreen] = useState<"phone" | "otp">("phone");
  const [country, setCountry] = useState("NG");
  const [phone, setPhone] = useState("");
  const [touched, setTouched] = useState(false);
  const [code, setCode] = useState(["", "", "", "", "", ""]);
  const [sendState, setSendState] = useState<"idle" | "sending">("idle");
  const [verifyState, setVerifyState] = useState<"idle" | "verifying" | "recovering">("idle");
  const [error, setError] = useState<string | null>(null);
  const [resendCooldown, setResendCooldown] = useState(0);
  const codeInputRefs = useRef<(HTMLInputElement | null)[]>([]);

  const e164 = normalizeE164(phone, country);
  const phoneError = touched ? validatePhone(phone, country) : null;
  const canSendCode = phone.trim().length > 0 && sendState === "idle";

  useEffect(() => {
    if (resendCooldown <= 0) return;
    const id = setInterval(() => setResendCooldown((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(id);
  }, [resendCooldown]);

  const sendCode = async () => {
    setTouched(true);
    setError(null);
    if (validatePhone(phone, country)) return;
    if (sendState !== "idle") return;

    setSendState("sending");
    // Supabase's own phone-OTP send — no custom OTP system, no locally
    // invented throttling beyond disabling this while a send/resend is
    // already in flight. Rate limiting is Supabase/provider's job.
    const { error: sendError } = await supabase.auth.signInWithOtp({ phone: e164 });
    setSendState("idle");

    if (sendError) {
      // Never say which part is wrong (unregistered vs. rate-limited vs.
      // provider failure) beyond a generic message — avoids turning this
      // into a phone-registered enumeration oracle.
      setError("We couldn't send a code to that number. Please check it and try again.");
      return;
    }

    setResendCooldown(RESEND_COOLDOWN_SECONDS);
    setScreen("otp");
  };

  const resend = async () => {
    if (resendCooldown > 0 || sendState !== "idle") return;
    setError(null);
    setSendState("sending");
    const { error: sendError } = await supabase.auth.signInWithOtp({ phone: e164 });
    setSendState("idle");
    if (sendError) {
      setError("We couldn't resend that code. Please try again.");
      return;
    }
    setResendCooldown(RESEND_COOLDOWN_SECONDS);
  };

  const verify = async (fullCode: string) => {
    if (verifyState !== "idle") return; // disable accidental duplicate submission
    setError(null);
    setVerifyState("verifying");

    // The actual proof of phone ownership — everything after this point
    // runs against a genuinely verified Supabase session, never a
    // client-asserted one.
    const { error: verifyError } = await supabase.auth.verifyOtp({ phone: e164, token: fullCode, type: "sms" });
    if (verifyError) {
      setVerifyState("idle");
      setError(
        verifyError.message.toLowerCase().includes("expired")
          ? "That code has expired. Send a new one."
          : "That code wasn't right. Please check it and try again.",
      );
      setCode(["", "", "", "", "", ""]);
      codeInputRefs.current[0]?.focus();
      return;
    }

    setVerifyState("recovering");
    const result = await recoverPlayerAccess();
    if (!result.ok) {
      setVerifyState("idle");
      setError(result.message);
      return;
    }

    router.push("/pass");
  };

  const handleCodeChange = (index: number, value: string) => {
    const digit = value.replace(/[^0-9]/g, "").slice(-1);
    const next = [...code];
    next[index] = digit;
    setCode(next);
    if (digit && index < 5) codeInputRefs.current[index + 1]?.focus();
    if (next.every((d) => d !== "")) verify(next.join(""));
  };

  const handleCodeKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace" && code[index] === "" && index > 0) {
      codeInputRefs.current[index - 1]?.focus();
    }
  };

  if (screen === "otp") {
    const maskedPhone = `${e164.slice(0, 4)} ••• ••• ${e164.slice(-4)}`;
    const verifying = verifyState !== "idle";

    return (
      <RegistrationShell step={2} total={2} onBack={() => setScreen("phone")}>
        <h1 className="rc-reg-prompt">Enter your code.</h1>
        <p className="rc-reg-subcopy">We sent a 6-digit code to {maskedPhone}</p>

        <div className="rc-access-otp-row" role="group" aria-label="6-digit verification code">
          {code.map((digit, i) => (
            <input
              key={i}
              ref={(el) => {
                codeInputRefs.current[i] = el;
              }}
              className="rc-access-otp-cell"
              inputMode="numeric"
              autoComplete={i === 0 ? "one-time-code" : "off"}
              maxLength={1}
              value={digit}
              disabled={verifying}
              autoFocus={i === 0}
              onChange={(e) => handleCodeChange(i, e.target.value)}
              onKeyDown={(e) => handleCodeKeyDown(i, e)}
              aria-label={`Digit ${i + 1}`}
            />
          ))}
        </div>

        {error ? (
          <p className="rc-reg-form-error" role="alert">
            <span aria-hidden="true">✕</span> {error}
          </p>
        ) : null}

        <div className="rc-reg-illustration">
          <Image
            src="/brand/v2/access-code.webp"
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
            disabled={code.some((d) => d === "")}
            loading={verifying}
            loadingLabel={verifyState === "recovering" ? "Opening your pass" : "Checking your code"}
            onClick={() => verify(code.join(""))}
          >
            Continue
          </Button>
          <button
            type="button"
            className="rc-access-resend"
            disabled={resendCooldown > 0 || sendState !== "idle" || verifying}
            onClick={resend}
          >
            Didn&rsquo;t get it?{" "}
            <span className="rc-access-resend-link">
              {resendCooldown > 0 ? `Send again (${resendCooldown}s)` : "Send again"}
            </span>
          </button>
        </div>
      </RegistrationShell>
    );
  }

  return (
    <RegistrationShell step={1} total={2} onBack={() => router.push("/")}>
      <h1 className="rc-reg-prompt">What&rsquo;s your WhatsApp number?</h1>
      <p className="rc-reg-subcopy">Use the number you joined RECESS with.</p>

      <div className="rc-reg-field">
        <Field
          id="access-phone"
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
            if (e.key === "Enter" && canSendCode) sendCode();
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
                disabled={sendState !== "idle"}
              >
                {COUNTRIES.map((c) => (
                  <option key={c.iso2} value={c.iso2}>
                    {c.name} (+{c.dialCode})
                  </option>
                ))}
              </select>
              <svg
                className="rc-reg-country-chevron"
                viewBox="0 0 12 8"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path d="M1 1.5 6 6.5 11 1.5" />
              </svg>
            </label>
          }
        />
      </div>

      {error ? (
        <p className="rc-reg-form-error" role="alert">
          <span aria-hidden="true">✕</span> {error}
        </p>
      ) : null}

      <div className="rc-reg-illustration">
        <Image
          src="/brand/v2/access-whatsapp.webp"
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
          disabled={!canSendCode}
          loading={sendState === "sending"}
          loadingLabel="Sending your code"
          onClick={sendCode}
        >
          Continue
        </Button>
      </div>
    </RegistrationShell>
  );
}
