/**
 * Environment access in one place.
 */
function required(value: string | undefined, name: string): string {
  if (!value) {
    throw new Error(
      `Missing environment variable ${name}. Check your .env.local file.`
    );
  }

  return value;
}

export const env = {
  supabaseUrl: () =>
    required(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      "NEXT_PUBLIC_SUPABASE_URL"
    ),

  supabaseAnonKey: () =>
    required(
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
      "NEXT_PUBLIC_SUPABASE_ANON_KEY"
    ),

  supabaseServiceRoleKey: () =>
    required(
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      "SUPABASE_SERVICE_ROLE_KEY"
    ),

  eventSlug: () =>
    process.env.NEXT_PUBLIC_RECESS_EVENT_SLUG ?? "recess-01",
};