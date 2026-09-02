import type { RegistrationState } from "./types";

/** "#024" — the schema's numeric player_number is never altered, only padded for display. */
export function formatPlayerNumber(n: number): string {
  return `#${String(n).padStart(3, "0")}`;
}

/**
 * "FRIDAY · 11 SEPT 2026" and "8:00 PM" — formatted in the EVENT's timezone,
 * not the viewer's. A player checking in from outside Lagos must see the
 * same date and time everyone else does; `timeZone` is what makes that true
 * regardless of the browser's local zone.
 */
export function formatEventDate(startsAt: string, timezone: string): string {
  const date = new Date(startsAt);
  const weekday = new Intl.DateTimeFormat("en-GB", { weekday: "long", timeZone: timezone })
    .format(date)
    .toUpperCase();
  const day = new Intl.DateTimeFormat("en-GB", { day: "numeric", timeZone: timezone }).format(date);
  const month = new Intl.DateTimeFormat("en-GB", { month: "short", timeZone: timezone })
    .format(date)
    .toUpperCase();
  const year = new Intl.DateTimeFormat("en-GB", { year: "numeric", timeZone: timezone }).format(date);
  return `${weekday} \u00B7 ${day} ${month} ${year}`;
}

export function formatEventTime(startsAt: string, timezone: string): string {
  const date = new Date(startsAt);
  return new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
    timeZone: timezone,
  }).format(date);
}

/** YYYYMMDDTHHMMSSZ, the .ics UTC form — startsAt is already an instant, so no timezone math is needed here. */
function toIcsUtc(iso: string): string {
  return new Date(iso).toISOString().replace(/[-:]/g, "").split(".")[0] + "Z";
}

function icsEscape(text: string): string {
  return text.replace(/[\\;,]/g, (m) => `\\${m}`).replace(/\n/g, "\\n");
}

/**
 * A minimal, dependency-free .ics file — no calendar API, no paid service.
 * Duration defaults to three hours; RECESS has no stored end time and a
 * game night reliably runs long, so a generous default beats a wrong one.
 */
export function buildEventIcs(registration: RegistrationState): string {
  const start = toIcsUtc(registration.startsAt);
  const end = toIcsUtc(new Date(new Date(registration.startsAt).getTime() + 3 * 60 * 60 * 1000).toISOString());
  const now = toIcsUtc(new Date().toISOString());

  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//RECESS//Registration//EN",
    "CALSCALE:GREGORIAN",
    "BEGIN:VEVENT",
    `UID:${registration.registrationId}@recess`,
    `DTSTAMP:${now}`,
    `DTSTART:${start}`,
    `DTEND:${end}`,
    `SUMMARY:${icsEscape(registration.eventName)}`,
    `DESCRIPTION:${icsEscape(`You're in as ${registration.alias}, player ${formatPlayerNumber(registration.playerNumber)}.`)}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");
}

export function downloadEventIcs(registration: RegistrationState) {
  const blob = new Blob([buildEventIcs(registration)], { type: "text/calendar;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${registration.eventSlug}.ics`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/**
 * The database already validates whatsapp_group_url as a real
 * chat.whatsapp.com invite (see is_whatsapp_group_url(), migration 0015);
 * this mirrors that shape client-side purely to decide whether to render a
 * live link or the "not published yet" state, never to gate the server.
 */
export function isValidWhatsAppGroupUrl(url: string | null): url is string {
  return !!url && /^https:\/\/chat\.whatsapp\.com\/(invite\/)?[A-Za-z0-9_-]{6,64}$/.test(url);
}
