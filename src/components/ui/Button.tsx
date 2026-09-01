import type { ReactNode } from "react";
import Link from "next/link";

export type ButtonVariant = "primary" | "secondary" | "ghost";

const base =
  "relative z-10 inline-flex items-center justify-between gap-4 rounded-rc-sm " +
  "transition-[transform,box-shadow,background-color] duration-100 ease-out " +
  "disabled:cursor-not-allowed";

const variants: Record<ButtonVariant, string> = {
  primary:
    "w-full min-h-tap px-6 bg-pink text-paper font-display text-rc-md shadow-press " +
    "active:translate-y-[3px] active:shadow-press-down " +
    "aria-disabled:bg-fg/10 aria-disabled:text-fg-soft aria-disabled:shadow-none aria-disabled:pointer-events-none",
  secondary:
    "w-full min-h-tap px-6 border-[1.5px] border-fg/20 text-fg font-display text-rc-md " +
    "active:translate-y-[2px] " +
    "aria-disabled:opacity-50 aria-disabled:pointer-events-none",
  ghost:
    "px-0 py-2 text-fg-soft text-rc-sm underline-offset-4 hover:underline " +
    "aria-disabled:opacity-50 aria-disabled:pointer-events-none",
};

type Props = {
  children: ReactNode;
  variant?: ButtonVariant;
  href?: string;
  disabled?: boolean;
  loading?: boolean;
  arrow?: boolean;
  type?: "button" | "submit";
  onClick?: () => void;
};

/**
 * Press is physical, not a hover lift — players are on touch screens.
 * `loading` is a first-class state because every important write in RECESS
 * has to show loading / success / failure / retry.
 */
export function Button({
  children,
  variant = "primary",
  href,
  disabled = false,
  loading = false,
  arrow = false,
  type = "button",
  onClick,
}: Props) {
  const inert = disabled || loading;
  const className = `${base} ${variants[variant]}`;

  const content = (
    <>
      <span>{loading ? "SENDING\u2026" : children}</span>
      {arrow && !loading ? <span aria-hidden="true">&rarr;</span> : null}
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
