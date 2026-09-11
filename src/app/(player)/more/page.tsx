import Link from "next/link";
import { Surface } from "@/components/ui/Surface";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { formatEventDate } from "@/features/registration/calendar";
import { isValidWhatsAppGroupUrl } from "@/features/registration/calendar";

/**
 * /more — secondary/static actions only. Event details, a WhatsApp entry
 * point only where the current player is actually entitled to see one, a
 * short "what is RECESS" note, and the coordinator entry point when this
 * player is also coordinating a room — mirroring the same banner already
 * shown on /pass, not a second, different mechanism. No settings, no
 * theme toggle, no admin controls.
 *
 * WhatsApp privacy: get_player_state() deliberately nulls
 * `event.whatsappGroupUrl` for every view except PASS_COUNTDOWN (see
 * that field's own comment in features/pass/types.ts) — the pre-event
 * group link isn't meant to linger once a player has moved on to
 * check-in/room stages. Once a player has an active room, the correct
 * link is the room's own `room.whatsappGroupUrl`, which is a genuinely
 * separate field the backend already scopes to "this player's own room
 * only." This page prefers that room link when present and only falls
 * back to the event-level one otherwise — never bypasses either
 * privacy rule to manufacture a link the state didn't actually provide.
 */
export default async function MorePage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status !== "registered") return null;
  const state = identity.state;

  const whatsapp = state.room?.whatsappGroupUrl ?? state.event.whatsappGroupUrl;
  const hasWhatsapp = isValidWhatsAppGroupUrl(whatsapp);

  return (
    <Surface as="main" grain="low" className="rc-more">
      <div className="rc-more-stage">
        <h1 className="rc-more-heading rc-numeric">{state.event.name}</h1>
        <p className="rc-more-date">
          {formatEventDate(state.event.startsAt, state.event.timezone)} · {state.event.timezoneLabel}
        </p>

        {state.coordinating ? (
          <Link href="/coordinate" className="rc-more-coord-entry">
            COORDINATING {state.coordinating.roomLabel} — GO TO ROOM <span aria-hidden="true">→</span>
          </Link>
        ) : null}

        {hasWhatsapp ? (
          <a href={whatsapp!} className="rc-more-whatsapp" target="_blank" rel="noreferrer">
            OPEN WHATSAPP GROUP <span aria-hidden="true">→</span>
          </a>
        ) : null}

        <section className="rc-more-about">
          <h2 className="rc-more-about-title">WHAT IS RECESS?</h2>
          <p className="rc-more-about-copy">
            RECESS is our night to embrace that inner child and have real fun — games, people, and a
            reason to log off for a few hours.
          </p>
        </section>
      </div>
    </Surface>
  );
}
