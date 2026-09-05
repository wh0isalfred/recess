import Image from "next/image";
import { Surface } from "@/components/ui/Surface";
import { Button } from "@/components/ui/Button";
import { RecessWordmarkV2 } from "@/components/brand/v2/RecessWordmark";
import { WhatIsRecess } from "@/features/landing/WhatIsRecess";
import type { PublicEventInfo } from "@/features/landing/event";

/**
 * Screen 02 Landing (V2). Replaces the old Screens 01 Arrival + 02 Landing
 * two-phase splash — see docs/SCREEN-STATUS.md for the history. This is now
 * the only state of `/`: no entrance timer, no crossfade, no sessionStorage
 * gate. A person opens RECESS and this is what they see.
 *
 * Composition (approved reference, screenshot 1):
 *   RECESS wordmark → ALL WORK. NO PLAY... → hero art (pawn + die) →
 *   NEXT RECESS / date / day·time·zone → I'M IN → WHAT IS RECESS?
 *
 * Real UI vs. brand art (see delivery report §3): the event label, date,
 * day, time, zone, and the CTA's destination/label are real DOM content
 * driven by `event` and `registered`, never baked into an image. The
 * wordmark, the "ALL WORK. NO PLAY..." lettering, and the pawn/die
 * composition are the three visual assets — a vector trace, a vector
 * trace, and an optimized raster, respectively (see report for why each
 * went the way it did).
 */
export function Landing({
  event,
  registered = false,
}: {
  event: PublicEventInfo;
  registered?: boolean;
}) {
  return (
    <Surface as="main" ground="paper" grain="high" className="rc-landing">
      <div className="rc-landing-frame">
        <div className="rc-landing-brand" role="img" aria-label="RECESS">
          <RecessWordmarkV2 className="rc-landing-wordmark" />
        </div>

        <h1 className="rc-landing-headline">
          <span className="sr-only">All work. No play&hellip;</span>
          <Image
            src="/brand/v2/all-work-no-play.svg"
            alt=""
            aria-hidden="true"
            width={555}
            height={508}
            priority
            className="rc-landing-headline-art"
          />
        </h1>

        <div className="rc-landing-hero" aria-hidden="true">
          <Image
            src="/brand/v2/hero-pawn-die.webp"
            alt=""
            width={684}
            height={300}
            priority
            className="rc-landing-hero-art"
          />
        </div>

        <div className="rc-landing-meta">
          <p className="rc-landing-eyebrow">Next RECESS</p>
          <p className="rc-landing-date rc-numeric">{event.dateLabel}</p>
          <p className="rc-landing-subline">
            <span>{event.dayLabel}</span>
            <span aria-hidden="true" className="rc-landing-dot">
              &middot;
            </span>
            <span>
              {event.timeLabel} {event.zoneLabel}
            </span>
          </p>
        </div>

        {registered ? (
          <Button href="/pass" variant="poster" size="lg" arrow>
            OPEN YOUR PASS
          </Button>
        ) : (
          <Button href="/register" variant="poster" size="lg" arrow>
            I&rsquo;M IN
          </Button>
        )}

        <WhatIsRecess />
      </div>
    </Surface>
  );
}
