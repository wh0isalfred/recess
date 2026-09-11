import Link from "next/link";
import { Surface } from "@/components/ui/Surface";
import { PlayMark } from "@/components/brand/PlayMark";
import { PosterLine } from "@/components/brand/RecessWordmark";
import type { RegistrationState } from "@/features/registration/types";
import { formatEventDate, formatPlayerNumber } from "@/features/registration/calendar";
import type { PlayerState } from "@/features/pass/types";
import { LiveStateRefresher } from "@/features/live/LiveStateRefresher";
import { PassCountdownScreen } from "./PassCountdownScreen";
import { CheckInScreen } from "./CheckInScreen";
import { RoomAssignedScreen } from "./RoomAssignedScreen";
import { WaitingForRoomScreen } from "./WaitingForRoomScreen";
import { LiveRoundScreen } from "./LiveRoundScreen";
import { BetweenRoundsScreen } from "./BetweenRoundsScreen";
import { BetweenGamesScreen } from "./BetweenGamesScreen";
import { PausedScreen } from "./PausedScreen";
import { QualifiedScreen } from "./QualifiedScreen";
import { NotQualifiedScreen } from "./NotQualifiedScreen";

/**
 * WAITLISTED's own screen — unchanged content from before this task, only
 * the props feeding it now come from get_player_state() rather than
 * get_my_registration(), adapted below by toRegistrationState().
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
 * A checked-in player in a state this system doesn't have a real screen
 * for yet must still land somewhere true, not blank or pretending to be
 * finished. LATE_ARRIVAL (the backend doesn't yet distinguish it from
 * ordinary ROOM_ASSIGNED) and RESULTS (no finale/final-results engine
 * exists — see docs/SCREEN-STATUS.md) are the only views still routed
 * here as of Phase 8.3 Gate B.
 */
function MinimalFallback({ state }: { state: PlayerState }) {
  const copy: Record<string, string> = {
    MISSED_CHECK_IN: "Check-in has moved on without you — find a coordinator at the venue.",
    EVENT_CANCELLED: "This RECESS has been cancelled.",
    CANCELLED: "This registration was cancelled.",
    LATE_ARRIVAL: "You're checked in. Find a coordinator to join a room.",
    RESULTS: "RECESS is done. Final results are being finalized.",
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
 * A small, persistent entry point to /coordinate — shown on top of
 * whichever view the player is otherwise seeing, since a coordinator is
 * still a normal player first (EVENT-OPS.md §1) and may be mid-Pass-
 * countdown, checked in, or anything else when they're assigned. Nothing
 * here is the authorization boundary — that's coordinator_room_state()
 * and every mutating RPC it fronts; this is only "is there a reason to
 * show this link at all."
 */
function CoordinatorBanner({ state }: { state: PlayerState }) {
  if (!state.coordinating) return null;
  return (
    <Link href="/coordinate" className="rc-coord-entry-banner">
      COORDINATING {state.coordinating.roomLabel} — GO TO ROOM →
    </Link>
  );
}

const DYNAMIC_VIEWS = new Set([
  "CHECKED_IN_WAITING",
  "ROOM_ASSIGNED",
  "LIVE_ROUND",
  "BETWEEN_ROUNDS",
  "BETWEEN_GAMES",
  "PAUSED",
  "QUALIFIED",
  "NOT_QUALIFIED",
]);

/**
 * Phase 8.2: PlayerShell is rendered once by the shared (player)/layout.tsx,
 * not per-view here. Phase 8.3 Gate B: every state below now ships on the
 * paper/light ground — the previous night-ground branches (WAITLISTED,
 * CHECK_IN_OPEN, ROOM_ASSIGNED, CHECKED_IN_WAITING, and the fallback) are
 * converted, with pass.css/check-in.css/room.css's own hardcoded ground
 * overrides and dark-background grid overlays fixed alongside the prop
 * change — not left behind unreadable.
 */
export function PassScreen({ state }: { state: PlayerState }) {
  return (
    <>
      <CoordinatorBanner state={state} />
      <LiveStateRefresher active={DYNAMIC_VIEWS.has(state.view)} />
      <PassScreenBody state={state} />
    </>
  );
}

function PassScreenBody({ state }: { state: PlayerState }) {
  if (state.view === "WAITLISTED") {
    return (
      <Surface as="main" grain="low" className="rc-pass">
        <div className="rc-pass-stage">
          <Waitlisted registration={toRegistrationState(state)} />
        </div>
      </Surface>
    );
  }

  if (state.view === "PASS_COUNTDOWN") {
    return <PassCountdownScreen state={state} />;
  }

  if (state.view === "CHECK_IN_OPEN") {
    return (
      <Surface as="main" grain="low" className="rc-chk">
        <CheckInScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "ROOM_ASSIGNED") {
    return (
      <Surface as="main" grain="low" className="rc-room">
        <RoomAssignedScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "CHECKED_IN_WAITING") {
    return (
      <Surface as="main" grain="low" className="rc-room">
        <WaitingForRoomScreen />
      </Surface>
    );
  }

  if (state.view === "LIVE_ROUND" && state.activeGame && state.room) {
    return (
      <Surface as="main" grain="low" className="rc-live">
        <LiveRoundScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "BETWEEN_ROUNDS" && state.activeGame && state.room) {
    return (
      <Surface as="main" grain="low" className="rc-live">
        <BetweenRoundsScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "BETWEEN_GAMES") {
    return (
      <Surface as="main" grain="low" className="rc-live">
        <BetweenGamesScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "PAUSED") {
    return (
      <Surface as="main" grain="low" className="rc-live">
        <PausedScreen />
      </Surface>
    );
  }

  if (state.view === "QUALIFIED") {
    return (
      <Surface as="main" grain="low" className="rc-live">
        <QualifiedScreen state={state} />
      </Surface>
    );
  }

  if (state.view === "NOT_QUALIFIED") {
    return (
      <Surface as="main" grain="low" className="rc-live">
        <NotQualifiedScreen state={state} />
      </Surface>
    );
  }

  return (
    <Surface as="main" grain="low" className="rc-pass">
      <div className="rc-pass-stage">
        <MinimalFallback state={state} />
      </div>
    </Surface>
  );
}
