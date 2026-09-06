"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function ResetPasswordForm() {
  const router = useRouter();
  const [supabase] = useState(() => createClient());

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  const [ready, setReady] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function initialiseRecovery() {
      setError(null);

      const hash = new URLSearchParams(
        window.location.hash.startsWith("#")
          ? window.location.hash.slice(1)
          : window.location.hash
      );

      const accessToken = hash.get("access_token");
      const refreshToken = hash.get("refresh_token");
      const type = hash.get("type");

      /*
       * Supabase dashboard recovery links currently arrive using
       * hash-based access_token + refresh_token values.
       *
       * Explicitly consume those credentials so they replace any
       * anonymous RECESS player session already in this browser.
       */
      if (
        type === "recovery" &&
        accessToken &&
        refreshToken
      ) {
        const { data, error } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });

        if (cancelled) return;

        if (error || !data.session) {
          setError(
            "This password recovery link is invalid or expired. Request a new one."
          );
          return;
        }

        const user = data.session.user;

        if (user.is_anonymous || !user.email) {
          await supabase.auth.signOut();
          setError(
            "This recovery link did not open the staff account. Request a new password recovery email."
          );
          return;
        }

        /*
         * Remove the sensitive recovery tokens from the address bar
         * after they have been consumed.
         */
        window.history.replaceState(
          {},
          document.title,
          window.location.pathname
        );

        setReady(true);
        return;
      }

      /*
       * Support refreshes after the recovery session has already
       * been established.
       */
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (cancelled) return;

      if (
        !session ||
        session.user.is_anonymous ||
        !session.user.email
      ) {
        setError(
          "No valid staff recovery session was found. Request a new recovery email."
        );
        return;
      }

      setReady(true);
    }

    initialiseRecovery();

    return () => {
      cancelled = true;
    };
  }, [supabase]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();

    if (submitting || !ready) return;

    setError(null);

    if (password.length < 8) {
      setError("Use at least 8 characters.");
      return;
    }

    if (password !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    setSubmitting(true);

    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user || user.is_anonymous || !user.email) {
      setSubmitting(false);
      setError(
        "The recovery session is not connected to your staff account."
      );
      return;
    }

    const { error } = await supabase.auth.updateUser({
      password,
    });

    if (error) {
      setSubmitting(false);
      setError(error.message);
      return;
    }

    await supabase.auth.signOut();

    router.replace("/admin/login");
    router.refresh();
  }

  if (!ready) {
    return (
      <p className="rc-admin-login-error" role="alert">
        {error ?? "VERIFYING RECOVERY LINK…"}
      </p>
    );
  }

  return (
    <form
      className="rc-admin-login-form"
      onSubmit={submit}
    >
      <label className="rc-admin-field">
        <span>New password</span>

        <input
          type="password"
          required
          minLength={8}
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </label>

      <label className="rc-admin-field">
        <span>Confirm new password</span>

        <input
          type="password"
          required
          minLength={8}
          autoComplete="new-password"
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
        />
      </label>

      {error ? (
        <p
          className="rc-admin-login-error"
          role="alert"
        >
          {error}
        </p>
      ) : null}

      <button
        type="submit"
        className="rc-admin-login-submit"
        disabled={submitting}
      >
        {submitting
          ? "UPDATING…"
          : "SET NEW PASSWORD"}
      </button>
    </form>
  );
}