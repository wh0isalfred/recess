"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { staffSignIn } from "@/features/admin/actions";

export function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await staffSignIn(email, password);
      if (!result.ok) {
        setSubmitting(false);
        setError(result.message);
        return;
      }
      router.push("/admin/overview");
      router.refresh();
    } catch {
      setSubmitting(false);
      setError("Something went wrong. Please try again.");
    }
  };

  return (
    <form className="rc-admin-login-form" onSubmit={submit}>
      <label className="rc-admin-field">
        <span>Email</span>
        <input
          type="email"
          required
          autoComplete="username"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </label>
      <label className="rc-admin-field">
        <span>Password</span>
        <input
          type="password"
          required
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </label>
      {error ? <p className="rc-admin-login-error" role="alert">{error}</p> : null}
      <button type="submit" className="rc-admin-login-submit" disabled={submitting}>
        {submitting ? "SIGNING IN…" : "SIGN IN"}
      </button>
    </form>
  );
}
