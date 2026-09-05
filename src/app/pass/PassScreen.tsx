import { Surface } from "@/components/ui/Surface";
import { PlayMark } from "@/components/brand/PlayMark";
import { PosterLine } from "@/components/brand/RecessWordmark";
import type { RegistrationState } from "@/features/registration/types";
import { formatEventDate, formatPlayerNumber } from "@/features/registration/calendar";
import type { PlayerState } from "@/features/pass/types";
import { PlayerShell } from "@/features/player-shell/PlayerShell";
import { PassCountdownScreen } from "./PassCountdownScreen";
import { CheckInScreen } from "./CheckInScreen";
import { RoomAssignedScreen } from "./RoomAssignedScreen";
import { WaitingForRoomScreen } from "./WaitingForRoomScreen";

/**
 * WAITLISTED's own screen — unchanged from before this task, only the props
 * feeding it now come from get_player_state() rather than
 * get_my_registration(), adapted below by toRegistrationState(). Out of
 * scope for the Pass V2 slice (the brief only covers PASS_COUNTDOWN); left
 * exactly as it was.
 */
function Waitlisted({ registration }: { registration: RegistrationState }) {
  return (
    <>
      <PlayMark className="rc-pass-mark" />
      <h1 className="rc-pass-heading">
        <PosterLine text="YOU'RE ON THE LIST." ratio={11.5} />
      </h1>
      <p className="rc-pass-alias rc-numeric">{registration.alias}</p>
      <p className="rc-pass-waitlist-copy">
        RECESS is full right now. You&rsquo;re {formatPlayerNumber(registration.playerNumber)} on the waitlist for{" "}
        {formatEventDate(registration.startsAt, registration.timezone)} — we&rsquo;ll reach out on WhatsApp if a
        spot opens up.
      </p>
    </>
  );
}

/**
 * A checked-in player in a state Screen 09 doesn't cover (LIVE, results,
 * event cancelled) must still land somewhere true, not blank or pretending
 * to be a finished screen. Plain, in the system's own type and colour.
 * CHECKED_IN_WAITING and ROOM_ASSIGNED have their own real screens now, so
 * they no longer route here — see the dispatch below.
 */
function MinimalFallback({ state }: { state: PlayerState }) {
  const copy: Record<string, string> = {
    MISSED_CHECK_IN: "Check-in has moved on without you — find a coordinator at the venue.",
    EVENT_CANCELLED: "This RECESS has been cancelled.",
    CANCELLED: "This registration was cancelled.",
    LATE_ARRIVAL: "You're checked in. Find a coordinator to join a room.",
    LIVE_ROUND: "RECESS is live right now.",
    BETWEEN_GAMES: "Between games right now.",
    PAUSED: "Play is paused right now.",
    RESULTS: "RECESS has wrapped — results are in.",
  };
  return (
    <>
      <PlayMark className="rc-pass-mark" />
      <p className="rc-pass-alias rc-numeric">{state.player.alias}</p>
      <p className="rc-pass-waitlist-copy">{copy[state.view] ?? "Check back soon."}</p>
    </>
  );
}

function toRegistrationState(state: PlayerState): RegistrationState {
  return {
    registrationId: `${state.event.slug}-${state.player.number}`,
    playerNumber: state.player.number,
    alias: state.player.alias,
    status: state.player.registrationStatus,
    eventId: state.event.slug,
    eventSlug: state.event.slug,
    eventName: state.event.name,
    startsAt: state.event.startsAt,
    timezone: state.event.timezone,
    timezoneLabel: state.event.timezoneLabel,
    whatsappGroupUrl: state.event.whatsappGroupUrl,
  };
}

/**
 * Registration Complete (src/features/registration/RegistrationComplete.tsx)
 * now handles the successful-registration moment in place, before ever
 * navigating here — so PASS_COUNTDOWN always renders the calm Pass V2
 * directly. The previous "fresh" celebration branch
 * (Confetti/Confirmed/hasPassFreshFlag) is gone: nothing calls
 * markPassFresh() anymore (confirmed via repository search before removing
 * this), so it was genuinely dead code, not just superseded — see the
 * delivery report.
 */
export function PassScreen({ state }: { state: PlayerState }) {
  if (state.view === "WAITLISTED") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-pass">
        <div className="rc-pass-stage">
          <Waitlisted registration={toRegistrationState(state)} />
        </div>
      </Surface>
    );
  }

  if (state.view === "PASS_COUNTDOWN") {
    return (
      <PlayerShell active="pass">
        <PassCountdownScreen state={state} />
      </PlayerShell>
    );
  }

  if (state.view === "CHECK_IN_OPEN") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-chk">
        <CheckInScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "ROOM_ASSIGNED") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-room">
        <RoomAssignedScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "CHECKED_IN_WAITING") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-room">
        <WaitingForRoomScreen />
      </Surface>
    );
  }

  return (
    <Surface as="main" ground="night" grain="low" className="rc-pass">
      <div className="rc-pass-stage">
        <MinimalFallback state={state} />
      </div>
    </Surface>
  );
}
