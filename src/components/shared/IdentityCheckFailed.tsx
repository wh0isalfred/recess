/**
 * What renders instead of onboarding or a redirect when
 * resolvePlayerIdentity() genuinely can't tell registered from
 * unregistered — a transient error, not a real "you have no registration"
 * answer. Deliberately plain: no ground-specific styling (the caller might
 * be any of the paper or night screens), just enough to tell the player
 * what happened and let them try again, rather than silently guessing.
 */
export function IdentityCheckFailed() {
  return (
    <main
      style={{
        minHeight: "100svh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "0.75rem",
        padding: "1.5rem",
        textAlign: "center",
        background: "var(--paper)",
        color: "var(--ink)",
        fontFamily: "var(--font-ui-family), system-ui, sans-serif",
      }}
    >
      <p style={{ fontWeight: 600 }}>Couldn&rsquo;t check your registration status.</p>
      <p style={{ fontSize: "0.875rem", color: "var(--ink-soft)" }}>Check your connection and try again.</p>
      <a
        href="."
        style={{
          marginTop: "0.5rem",
          padding: "0.75rem 1.5rem",
          borderRadius: "0.625rem",
          background: "var(--accent)",
          color: "var(--paper)",
          textDecoration: "none",
          fontWeight: 700,
        }}
      >
        RETRY
      </a>
    </main>
  );
}
