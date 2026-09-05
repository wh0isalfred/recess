/**
 * The play mark — three figures under a burst. Same glyph as the arrival
 * splash; duplicated here rather than imported from ArrivalLanding.tsx,
 * which is approved and untouched. Inherits `currentColor`.
 */
export function PlayMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 72 52"
      className={className}
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M36 3v5M25 6l2.5 4.5M47 6l-2.5 4.5M17 13l4 2.8M55 13l-4 2.8" />
      <circle cx="36" cy="20" r="4.6" fill="currentColor" stroke="none" />
      <path d="M36 25.5v9M27.5 29.5 36 27l8.5 2.5M36 34.5l-5 8M36 34.5l5 8" />
      <circle cx="14" cy="25" r="4" fill="currentColor" stroke="none" />
      <path d="M14 29.5v8M6.5 33 14 31l7.5 2M14 37.5l-4.5 7M14 37.5l4.5 7" />
      <circle cx="58" cy="25" r="4" fill="currentColor" stroke="none" />
      <path d="M58 29.5v8M50.5 33 58 31l7.5 2M58 37.5l-4.5 7M58 37.5l4.5 7" />
    </svg>
  );
}
