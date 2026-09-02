import { findCountry } from "./countries";

/**
 * Mirrors, in TypeScript, the same three checks register_player() makes in
 * SQL — see supabase/migrations/20260901001600_registration.sql. This copy
 * exists for responsive UX (disabling CLAIM MY SPOT, inline field errors)
 * only. It is not the authority: the database re-validates everything on
 * submission and wins any disagreement, by design — see the migration
 * header and CLAUDE.md's operating rule.
 */

export function validateName(raw: string): string | null {
  const name = raw.trim();
  if (name.length === 0) return "Enter your name.";
  if (name.length > 120) return "That name is too long.";
  return null;
}

export function validateAlias(raw: string): string | null {
  const alias = raw.trim();
  if (alias.length === 0) return "Choose a RECESS name.";
  if (!/^[A-Za-z0-9._-]{2,24}$/.test(alias)) {
    return "2-24 letters, numbers, dots, underscores or hyphens.";
  }
  return null;
}

/**
 * `raw` is the local part exactly as typed — digits and the formatting a
 * person naturally types (spaces, dashes, parentheses). Those are stripped
 * before the length/shape check runs.
 */
export function validatePhone(raw: string, countryIso2: string): string | null {
  const digits = raw.replace(/[^0-9]/g, "");
  if (digits.length === 0) return "Enter your WhatsApp number.";
  const country = findCountry(countryIso2);
  // A soft range around the expected length — catches a mistyped digit or a
  // half-entered number without being pedantic about the true national rules
  // for all 30-odd countries in the list. The server's E.164 shape check
  // (7-15 digits total after the +) is what actually gates submission.
  if (digits.length < country.nsnLength - 1 || digits.length > country.nsnLength + 2) {
    return "That doesn't look like a full number.";
  }
  return null;
}

export function normalizeE164(raw: string, countryIso2: string): string {
  const country = findCountry(countryIso2);
  let digits = raw.replace(/[^0-9]/g, "");
  // A person who includes a leading 0 on the national number ("0801...")
  // types the number the way they always have; drop it before the country
  // code is prefixed, the way every WhatsApp-adjacent phone field does.
  if (digits.startsWith("0")) digits = digits.slice(1);
  return `+${country.dialCode}${digits}`;
}

export function validateConsent(consent: boolean): string | null {
  return consent ? null : "Required to continue.";
}
