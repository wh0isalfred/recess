"use client";

import { useState } from "react";
import Link from "next/link";
import { Surface } from "@/components/ui/Surface";
import { Field } from "@/components/ui/Field";
import { PawnMark } from "@/components/brand/PawnMark";
import { BrushGesture, PosterLine, RecessWordmark } from "@/components/brand/RecessWordmark";

/**
 * Screen 03 — Registration / Name. Step 1 of 3.
 *
 * Visual pass only: the name is held in local state and NEXT goes nowhere.
 * No Supabase, no player record, no alias, no capacity check — that is the
 * CONNECT step, and screens 04 and 05 do not exist yet.
 */
export function NameStep() {
  const [name, setName] = useState("");

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
            <span className="rc-reg-count rc-numeric">1 / 3</span>
            <span className="rc-reg-dots" role="img" aria-label="Step 1 of 3">
              <span className="rc-reg-dot rc-reg-dot--on" />
              <span className="rc-reg-dot" />
              <span className="rc-reg-dot" />
            </span>
          </div>
        </div>

        <div className="rc-reg-mark">
          <RecessWordmark />
          <BrushGesture className="rc-reg-gesture" />
          <span className="sr-only">RECESS</span>
        </div>

        <h1 className="rc-reg-heading">
          <span className="sr-only">Let&rsquo;s get you in.</span>
          <PosterLine text={"LET\u2019S GET YOU IN."} />
        </h1>

        <div className="rc-reg-field">
          <Field
            id="player-name"
            label="What's your name?"
            name="name"
            autoComplete="given-name"
            autoCapitalize="words"
            enterKeyHint="next"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </div>

        <div className="rc-reg-foot">
          <PawnMark className="rc-reg-pawn" />
          <button type="button" className="rc-reg-next" disabled={name.trim().length === 0}>
            NEXT <span aria-hidden="true">→</span>
          </button>
        </div>
      </div>
    </Surface>
  );
}
