"use client";

import { useId, useRef, useState } from "react";

/**
 * `WHAT IS RECESS?` has no existing destination anywhere in the product —
 * checked before building this (no route, no section, no doc anchor). Per
 * the brief: implement the smallest coherent behavior rather than invent a
 * marketing page. This reveals one concise, already-approved line (the same
 * copy used in the page's own metadata description) in place, and closes
 * again on a second tap — a disclosure, not a navigation.
 */
export function WhatIsRecess() {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const panelRef = useRef<HTMLParagraphElement>(null);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    if (next) {
      // Only on open — closing shouldn't yank the scroll position back
      // down. A short delay lets `hidden` actually clear before measuring.
      requestAnimationFrame(() => {
        panelRef.current?.scrollIntoView({ behavior: "smooth", block: "nearest" });
      });
    }
  };

  return (
    <div className="rc-landing-explain">
      <button
        type="button"
        className="rc-landing-explain-toggle"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={toggle}
      >
        WHAT IS RECESS?
      </button>
      <p
        ref={panelRef}
        id={panelId}
        className="rc-landing-explain-panel"
        data-open={open}
        hidden={!open}
      >
        RECESS is our night to embrace that inner child and have real fun —
        games, people, and a reason to log off for a few hours.
      </p>
    </div>
  );
}
