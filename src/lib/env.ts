/**
 * Environment access in one place, validated at the point of use rather than
 * at import time — a missing key must not break `next build`, it must break
 * the request that needed it, with a message that says what to do.
 */
function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing environment variable ${name}. Copy .env.example to .env.local and fill it in.`
    );
  }
  return value;
}

export const env = {
  supabaseUrl: () => required("NEXT_PUBLIC_SUPABASE_URL"),
  supabaseAnonKey: () => required("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
  supabaseServiceRoleKey: () => required("SUPABASE_SERVICE_ROLE_KEY"),
  eventSlug: () => process.env.NEXT_PUBLIC_RECESS_EVENT_SLUG ?? "recess-01",
};
