import type { ReactNode } from "react";
import Link from "next/link";

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
export type ButtonSize = "lg" | "sm";

const base =
  "relative z-10 inline-flex items-center justify-center gap-3 font-display " +
  "transition-[transform,box-shadow,background-color,color] " +
  "duration-[var(--t-press)] ease-[var(--ease-press)] " +
  "aria-disabled:pointer-events-none aria-disabled:shadow-none";

const sizes: Record<ButtonSize, string> = {
  lg: "min-h-tap w-full px-6 text-rc-md",
  sm: "min-h-tap-sm px-5 text-rc-base",
};

const variants: Record<ButtonVariant, string> = {
  // The signature control. Pink fill, cream label, hard offset that collapses
  // under the thumb. Label is display type at 20px so the 3.6:1 fill/label
  // pair clears WCAG large-text.
  primary:
    "rounded-control bg-accent text-paper shadow-control " +
    "active:translate-y-[3px] active:shadow-control-pressed " +
    "aria-disabled:bg-fg-muted aria-disabled:text-fg-soft",
  secondary:
    "rounded-control border-[length:var(--hairline)] border-fg-line text-fg " +
    "active:translate-y-[2px] active:bg-fg-muted " +
    "aria-disabled:opacity-50",
  danger:
    "rounded-control bg-alert text-paper " +
    "active:translate-y-[2px] aria-disabled:opacity-50",
  // Not a button pretending to be a link. A link that happens to be tappable.
  ghost:
    "min-h-tap-sm px-0 font-ui text-rc-sm text-fg-soft underline " +
    "decoration-fg-line underline-offset-4 hover:decoration-current " +
    "aria-disabled:opacity-50",
};

type Props = {
  children: ReactNode;
  variant?: ButtonVariant;
  size?: ButtonSize;
  href?: string;
  disabled?: boolean;
  /** Shows a spinner and blocks repeat presses. Every write in RECESS has one. */
  loading?: boolean;
  loadingLabel?: string;
  /** Only on controls that move the night forward. Not decoration. */
  arrow?: boolean;
  type?: "button" | "submit";
  onClick?: () => void;
};

function Spinner() {
  return (
    <span
      aria-hidden="true"
      className="inline-block size-4 animate-spin rounded-pill border-2 border-current border-t-transparent motion-reduce:animate-none"
    />
  );
}

export function Button({
  children,
  variant = "primary",
  size = "lg",
  href,
  disabled = false,
  loading = false,
  loadingLabel = "Sending",
  arrow = false,
  type = "button",
  onClick,
}: Props) {
  const inert = disabled || loading;
  const className = [
    base,
    variant === "ghost" ? "" : sizes[size],
    variants[variant],
    variant === "primary" || variant === "secondary" ? "justify-between" : "",
  ]
    .filter(Boolean)
    .join(" ");

  const content = loading ? (
    <>
      <span>{loadingLabel}</span>
      <Spinner />
    </>
  ) : (
    <>
      <span>{children}</span>
      {arrow ? <span aria-hidden="true">&rarr;</span> : null}
    </>
  );

  if (href && !inert) {
    return (
      <Link href={href} className={className}>
        {content}
      </Link>
    );
  }

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={inert}
      aria-disabled={inert || undefined}
      aria-busy={loading || undefined}
      className={className}
    >
      {content}
    </button>
  );
}
