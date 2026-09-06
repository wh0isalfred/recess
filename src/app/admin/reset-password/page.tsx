import type { Metadata } from "next";
import { ResetPasswordForm } from "./ResetPasswordForm";

export const metadata: Metadata = {
  title: "Reset password — RECESS",
};

export default function ResetPasswordPage() {
  return (
    <main className="rc-admin-login">
      <div className="rc-admin-login-card">
        <p className="rc-admin-login-mark">RECESS</p>
        <h1 className="rc-admin-login-title">Reset password</h1>
        <ResetPasswordForm />
      </div>
    </main>
  );
}