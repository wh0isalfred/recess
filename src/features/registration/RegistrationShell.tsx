"use client";

import type { ReactNode } from "react";
import { Surface } from "@/components/ui/Surface";
import { RecessWordmarkV2 } from "@/components/brand/v2/RecessWordmark";

/**
 * V2 onboarding shell — shared chrome for Name/Alias/WhatsApp.
 *
 * Replaces the V1 shell (X-close, dot progress, wordmark+brush lockup) with
 * the approved V2 treatment: a back chevron whose destination/behavior each
 * step controls (step 1 leaves to Landing; steps 2-3 step back preserving
 * their own draft field — see each Step's own `back()`), the canonical V2
 * wordmark centered, a step counter, and a three-segment fill bar instead of
 * dots. Registration is deliberately quieter than Landing (BRAND.md:
 * acquisition is expressive, product is disciplined) — no pawn/die hero
 * poster here, low grain, real UI text instead of poster lettering.
 *
 * `hideChrome` drops the header entirely for the post-submit Registration
 * Complete transition (WhatsAppStep) — that moment is a transition, not
 * another onboarding step, and showing "3/3" over a success mark would be
 * exactly the "additional confirmation screen" the brief says not to add.
 */
export function RegistrationShell({
  step,
  total = 3,
  onBack,
  hideChrome = false,
  children,
}: {
  step: number;
  total?: number;
  onBack?: () => void;
  hideChrome?: boolean;
  children: ReactNode;
}) {
  return (
    <Surface as="main" ground="paper" grain="low" className="rc-reg">
      <div className="rc-reg-stage">
        {hideChrome ? null : (
          <>
            <div className="rc-reg-top">
              <button
                type="button"
                className="rc-reg-back-chevron"
                onClick={onBack}
                aria-label="Back"
              >
                <svg viewBox="0 0 12 20" fill="none" stroke="currentColor" strokeWidth="2.2"
                  strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M10 2 2 10l8 8" />
                </svg>
              </button>

              <div className="rc-reg-mark" role="img" aria-label="RECESS">
                <RecessWordmarkV2 />
              </div>

              <span className="rc-reg-count rc-numeric">
                {step} / {total}
              </span>
            </div>

            <div className="rc-reg-progress" role="img" aria-label={`Step ${step} of ${total}`}>
              {Array.from({ length: total }, (_, i) => (
                <span
                  key={i}
                  className={`rc-reg-progress-seg${i < step ? " rc-reg-progress-seg--on" : ""}`}
                />
              ))}
            </div>
          </>
        )}

        {children}
      </div>
    </Surface>
  );
}
