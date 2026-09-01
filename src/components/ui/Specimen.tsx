import type { ReactNode } from "react";

/**
 * Lab chrome only. Nothing in this file is part of the RECESS design system —
 * it is the wall the specimens hang on, and it deliberately looks like a lab
 * rather than like RECESS so the two are never confused.
 */
export function Section({
  title,
  note,
  children,
}: {
  title: string;
  note?: string;
  children: ReactNode;
}) {
  return (
    <section className="border-t border-neutral-300 py-12">
      <div className="mx-auto max-w-5xl px-6">
        <h2 className="font-display text-2xl text-neutral-900">{title}</h2>
        {note ? (
          <p className="mt-2 max-w-[60ch] text-sm text-neutral-600">{note}</p>
        ) : null}
        <div className="mt-8">{children}</div>
      </div>
    </section>
  );
}

export function Row({
  caption,
  children,
  cols = "auto",
}: {
  caption?: string;
  children: ReactNode;
  cols?: "auto" | "two";
}) {
  return (
    <div className="mb-8 last:mb-0">
      {caption ? (
        <p className="mb-3 font-mono text-xs text-neutral-500">{caption}</p>
      ) : null}
      <div
        className={
          cols === "two"
            ? "grid gap-6 md:grid-cols-2"
            : "flex flex-wrap items-start gap-6"
        }
      >
        {children}
      </div>
    </div>
  );
}

/** A phone-width frame, because every player component is designed at 390px. */
export function Phone({
  children,
  caption,
}: {
  children: ReactNode;
  caption: string;
}) {
  return (
    <figure className="w-[390px] max-w-full shrink-0">
      <div className="overflow-hidden rounded-xl border border-neutral-300">
        {children}
      </div>
      <figcaption className="mt-2 font-mono text-xs text-neutral-500">
        {caption}
      </figcaption>
    </figure>
  );
}
