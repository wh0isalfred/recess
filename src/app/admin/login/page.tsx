import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getStaffSession } from "@/features/admin/actions";
import { LoginForm } from "./LoginForm";

export const metadata: Metadata = { title: "Staff sign in — RECESS" };

export default async function AdminLoginPage() {
  const staff = await getStaffSession();
  if (staff) redirect("/admin/events");

  return (
    <main className="rc-admin-login">
      <div className="rc-admin-login-card">
        <p className="rc-admin-login-mark">RECESS</p>
        <h1 className="rc-admin-login-title">Staff sign in</h1>
        <LoginForm />
      </div>
    </main>
  );
}
