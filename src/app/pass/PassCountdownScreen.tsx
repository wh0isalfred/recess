import Image from "next/image";
import { RecessWordmarkV2 } from "@/components/brand/v2/RecessWordmark";
import { PlayerIdentity } from "@/features/player-shell/PlayerIdentity";
import type { PlayerState } from "@/features/pass/types";
import { formatDateOnly, formatWeekdayOnly } from "@/features/pass/v2/format";
import { formatEventTime } from "@/features/registration/calendar";
import { WhatsAppCta } from "@/features/pass/v2/WhatsAppCta";
import { SocialProof } from "@/features/pass/v2/SocialProof";

/**
 * Pass V2, PASS_COUNTDOWN. One job: tell the player what's happening and
 * give them the one thing to do next (before the event, that's WhatsApp).
 * No game list, no dashboard — Games/Players/More own that content now.
 *
 * Reuses Landing's canonical V2 hero assets (wordmark, "ALL WORK. NO
 * PLAY...", pawn/die composition) rather than exporting new copies — the
 * brief is explicit that a different layout position is not a new asset.
 */
export function PassCountdownScreen({ state }: { state: PlayerState }) {
  const { event, player, socialProof } = state;

  return (
    <div className="rc-pass2-stage">
      <header className="rc-pass2-top">
        <div className="rc-pass2-brand" role="img" aria-label="RECESS">
          <RecessWordmarkV2 className="rc-pass2-wordmark" />
        </div>
        <PlayerIdentity alias={player.alias} playerNumber={player.number} avatarColor={player.avatarColor} />
      </header>

      <h1 className="rc-pass2-headline">
        <span className="sr-only">All work. No play&hellip;</span>
        <Image
          src="/brand/v2/all-work-no-play.svg"
          alt=""
          aria-hidden="true"
          width={555}
          height={508}
          priority
          className="rc-pass2-headline-art"
        />
      </h1>

      <div className="rc-pass2-hero" aria-hidden="true">
        <Image
          src="/brand/v2/hero-pawn-die.webp"
          alt=""
          width={684}
          height={300}
          priority
          className="rc-pass2-hero-art"
        />
      </div>

      <div className="rc-pass2-event">
        <p className="rc-pass2-eyebrow">NEXT RECESS</p>
        <p className="rc-pass2-date rc-numeric">{formatDateOnly(event.startsAt, event.timezone)}</p>
        <p className="rc-pass2-subline">
          <span>{formatWeekdayOnly(event.startsAt, event.timezone)}</span>
          <span aria-hidden="true" className="rc-pass2-dot">
            &middot;
          </span>
          <span>
            {formatEventTime(event.startsAt, event.timezone)} {event.timezoneLabel}
          </span>
        </p>
      </div>

      <WhatsAppCta
        whatsappGroupUrl={event.whatsappGroupUrl}
        eventId={event.id}
        registrationId={player.registrationId}
      />

      {socialProof ? <SocialProof socialProof={socialProof} /> : null}
    </div>
  );
}
