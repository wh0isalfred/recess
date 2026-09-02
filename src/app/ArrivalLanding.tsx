"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Surface } from "@/components/ui/Surface";
import { BrushGesture, RecessWordmark } from "@/components/brand/RecessWordmark";

/**
 * Screens 01 Arrival + 02 Landing.
 *
 * Two states of `/`, not two routes. The server always renders the splash
 * phase; whether it is actually *seen* is decided before paint by the guard
 * script in page.tsx, which sets `html[data-arrival="fresh"]` only on the
 * first arrival of a browser session and never under prefers-reduced-motion.
 * All the splash styling hangs off that attribute, so a returning visitor
 * lands straight on the hero with no flash and no hydration mismatch, and
 * this component's only job is to release the phase after the entrance.
 */

const ENTRANCE_MS = 880;

export type EventCard = {
  /** "FRI" */
  day: string;
  /** "11" */
  date: string;
  /** "SEPT 2026" */
  monthYear: string;
  /** "8:00" */
  time: string;
  /** "PM" */
  meridiem: string;
  /** "WAT" */
  zone: string;
};

export function ArrivalLanding({ event }: { event: EventCard }) {
  const [phase, setPhase] = useState<"splash" | "landing">("splash");

  useEffect(() => {
    const timer = setTimeout(() => setPhase("landing"), ENTRANCE_MS);
    return () => clearTimeout(timer);
  }, []);

  return (
    <Surface as="main" ground="paper" grain="low" className="rc-arrival">
      <div className="rc-arrival-frame" data-phase={phase}>
        {/* Approved artwork. Paper, grain, people mark, die and spatter all
            live in these two files and are never redrawn in CSS. */}
        <div className="rc-arrival-art rc-arrival-art--landing" aria-hidden="true" />
        <div className="rc-arrival-art rc-arrival-art--entrance" aria-hidden="true" />

        <div className="rc-arrival-stage">
          <Link href="#next-recess" className="rc-arrival-next rc-arrival-reveal">
            Next RECESS <span aria-hidden="true">↗</span>
          </Link>

          <div className="rc-arrival-mast">
            <p className="rc-arrival-eyebrow">
              <span className="rc-arrival-eyebrow-in">
                ALL WORK. <em>NO PLAY...</em>
              </span>
            </p>

            <h1>
              <span className="sr-only">RECESS</span>
              <span className="rc-arrival-wordmark-in">
                <RecessWordmark className="rc-arrival-wordmark" />
              </span>
            </h1>

            <span className="rc-arrival-gesture-in">
              <BrushGesture className="rc-arrival-gesture" />
            </span>
          </div>

          <div className="rc-arrival-body rc-arrival-reveal">
            {/* The reference breaks these lines deliberately — it is set
                copy, not a paragraph that happens to wrap. */}
            <p className="rc-arrival-lede">
              RECESS is our night
              <br />
              to embrace that inner child
              <br />
              and have <em>real fun.</em>
            </p>

            <div className="rc-arrival-meta rc-numeric">
              <div className="rc-arrival-meta-col">
                <span className="rc-arrival-label">{event.day}</span>
                <span className="rc-arrival-figure rc-arrival-figure--day">{event.date}</span>
                <span className="rc-arrival-label">{event.monthYear}</span>
              </div>
              <div className="rc-arrival-meta-col">
                <span className="rc-arrival-figure rc-arrival-figure--time">{event.time}</span>
                <span className="rc-arrival-figure rc-arrival-figure--meridiem">
                  {event.meridiem}
                </span>
                <span className="rc-arrival-label rc-arrival-label--accent">{event.zone}</span>
              </div>
            </div>

            <Link href="/register" className="rc-arrival-cta">
              I&rsquo;M IN <span aria-hidden="true">→</span>
            </Link>

            <p className="rc-arrival-note">Come solo or bring your people.</p>
          </div>

          <div className="rc-arrival-hint rc-arrival-reveal" aria-hidden="true">
            <svg viewBox="0 0 24 14" fill="none" stroke="currentColor" strokeWidth="2.6"
              strokeLinecap="round" strokeLinejoin="round">
              <path d="M2 2l10 10L22 2" />
            </svg>
          </div>
        </div>
      </div>
    </Surface>
  );
}
