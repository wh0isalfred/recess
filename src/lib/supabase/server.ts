import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";
import { env } from "@/lib/env";

/**
 * Server client for React Server Components and route handlers. Still the
 * anon key, still subject to RLS — it simply reads the session from cookies.
 *
 * Async because `cookies()` returns a promise from Next 15 onward.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(env.supabaseUrl(), env.supabaseAnonKey(), {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (
        items: { name: string; value: string; options: CookieOptions }[]
      ) => {
        try {
          items.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        } catch {
          // Called from a Server Component, where cookies are read-only.
          // Middleware refreshes the session instead. Safe to ignore.
        }
      },
    },
  });
}
