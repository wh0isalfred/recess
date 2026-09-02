"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { Surface } from "@/components/ui/Surface";
import { BrushGesture, RecessWordmark } from "@/components/brand/RecessWordmark";

/**
 * The chrome every registration step shares: paper ground, the leave control,
 * the step counter over its dots, and the small RECESS lockup. Extracted from
 * Screen 03 unchanged — the markup and classes are identical, so 03 renders
 * exactly as approved.
 *
 * Everything below the lockup is the step's own composition and stays in the
 * step, because no two of them are laid out the same way.
 */
export function RegistrationShell({
  step,
  total = 3,
  children,
}: {
  step: number;
  total?: number;
  children: ReactNode;
}) {
  return (
    <Surface as="main" ground="paper" grain="mid" className="rc-reg">
      <div className="rc-reg-stage">
        <div className="rc-reg-top">
          <Link href="/" className="rc-reg-close" aria-label="Leave registration">
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2.2"
              strokeLinecap="round" aria-hidden="true">
              <path d="M3 3l14 14M17 3L3 17" />
            </svg>
          </Link>

          <div className="rc-reg-steps">
            <span className="rc-reg-count rc-numeric">
              {step} / {total}
            </span>
            <span className="rc-reg-dots" role="img" aria-label={`Step ${step} of ${total}`}>
              {Array.from({ length: total }, (_, i) => (
                <span
                  key={i}
                  className={`rc-reg-dot${i < step ? " rc-reg-dot--on" : ""}`}
                />
              ))}
            </span>
          </div>
        </div>

        <div className="rc-reg-mark">
          <RecessWordmark />
          <BrushGesture className="rc-reg-gesture" />
          <span className="sr-only">RECESS</span>
        </div>

        {children}
      </div>
    </Surface>
  );
}
