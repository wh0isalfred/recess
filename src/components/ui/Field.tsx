"use client";

import type { InputHTMLAttributes, ReactNode } from "react";

type Props = {
  id: string;
  label: string;
  /** Sits above the input, because it changes how you fill it in. */
  hint?: string;
  error?: string;
  /** Confirmation after a successful async check, e.g. an alias being free. */
  success?: string;
  /** For the country-code selector in front of a phone number. */
  prefix?: ReactNode;
} & Omit<InputHTMLAttributes<HTMLInputElement>, "id" | "className" | "prefix">;

/**
 * One input, one label, one message. Registration is three of these across
 * three steps, never a single long form.
 *
 * Error and success are never colour alone: each carries its own glyph and
 * its own words, and the input border changes shape-of-state too.
 */
export function Field({
  id,
  label,
  hint,
  error,
  success,
  prefix,
  ...input
}: Props) {
  const describedBy = [
    hint ? `${id}-hint` : null,
    error ? `${id}-error` : null,
    success && !error ? `${id}-success` : null,
  ]
    .filter(Boolean)
    .join(" ");

  const borderTone = error
    ? "border-alert"
    : success
      ? "border-go"
      : "border-fg-line focus-within:border-accent";

  return (
    <div className="relative z-10 block">
      <label htmlFor={id} className="mb-2 block text-rc-base font-medium text-fg">
        {label}
      </label>

      {hint ? (
        <p id={`${id}-hint`} className="mb-2 text-rc-sm text-fg-soft">
          {hint}
        </p>
      ) : null}

      <div
        className={`flex min-h-tap items-stretch overflow-hidden rounded-control border-[length:var(--hairline)] bg-field ${borderTone}`}
      >
        {prefix ? (
          <div className="flex items-center border-r-[length:var(--hairline)] border-fg-line px-3 text-rc-base text-fg-soft">
            {prefix}
          </div>
        ) : null}
        <input
          id={id}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy || undefined}
          className="min-w-0 flex-1 bg-transparent px-4 text-rc-base text-fg outline-none placeholder:text-fg-placeholder"
          {...input}
        />
      </div>

      {error ? (
        <p id={`${id}-error`} className="mt-2 flex gap-2 text-rc-sm text-alert">
          <span aria-hidden="true">✕</span>
          {error}
        </p>
      ) : success ? (
        <p id={`${id}-success`} className="mt-2 flex gap-2 text-rc-sm text-go">
          <span aria-hidden="true">✓</span>
          {success}
        </p>
      ) : null}
    </div>
  );
}
