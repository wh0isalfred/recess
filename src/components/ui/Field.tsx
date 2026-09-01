"use client";

import type { InputHTMLAttributes } from "react";

type Props = {
  id: string;
  label: string;
  hint?: string;
  error?: string;
} & Omit<InputHTMLAttributes<HTMLInputElement>, "id" | "className">;

/**
 * One input, one label, one error. Registration is three of these across
 * three steps, never a giant form.
 */
export function Field({ id, label, hint, error, ...input }: Props) {
  const describedBy = [hint ? `${id}-hint` : null, error ? `${id}-error` : null]
    .filter(Boolean)
    .join(" ");

  return (
    <div className="relative z-10 block">
      <label htmlFor={id} className="mb-2 block text-rc-sm text-fg-soft">
        {label}
      </label>

      {hint ? (
        <p id={`${id}-hint`} className="mb-2 text-rc-sm text-fg-soft">
          {hint}
        </p>
      ) : null}

      <input
        id={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy || undefined}
        className={
          "w-full min-h-tap rounded-rc-sm border-[1.5px] bg-field px-4 " +
          "text-rc-base text-fg placeholder:text-fg-placeholder " +
          (error ? "border-pink-deep" : "border-fg-line focus:border-pink")
        }
        {...input}
      />

      {error ? (
        <p id={`${id}-error`} className="mt-2 text-rc-sm text-pink-deep">
          {error}
        </p>
      ) : null}
    </div>
  );
}
