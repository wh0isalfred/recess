"use client";

import { useCallback, useEffect, useState } from "react";
import {
  completeRoomGame,
  fetchCoordinatorRoomState,
  fetchRoomStandings,
  startRoomGame,
  startRound,
} from "./actions";
import type { CoordinatorRoomState, RoomStandingRow, RoundSnapshot } from "./types";
import { ResultEntryFlow } from "./ResultEntryFlow";
import { GameTimer } from "./GameTimer";
import { CorrectionRequestPanel } from "./CorrectionRequestPanel";
import { Surface } from "@/components/ui/Surface";

type Phase = "loading" | "error" | "home" | "result-entry" | "standings-and-next";

export function CoordinateView({ roomId, roomLabel }: { roomId: string; roomLabel: string }) {
  const [phase, setPhase] = useState<Phase>("loading");
  const [state, setState] = useState<CoordinatorRoomState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activeRound, setActiveRound] = useState<RoundSnapshot | null>(null);
  const [standings, setStandings] = useState<RoomStandingRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [correctionRoundId, setCorrectionRoundId] = useState<string | null>(null);

  const reload = useCallback(async () => {
    const result = await fetchCoordinatorRoomState(roomId);
    if (!result.ok) {
      setError(result.message);
      setPhase("error");
      return;
    }
    setState(result.data);
    setError(null);
    // A round already LIVE on reload (refresh mid-game) drops straight
    // back into result entry, using the room's real live round rather
    // than any locally-remembered snapshot — "recover authoritative state
    // from the backend rather than trusting stale local UI state."
    if (result.data.currentGame?.liveRound) {
      setActiveRound({
        roundId: result.data.currentGame.liveRound.roundId,
        roundIndex: result.data.currentGame.liveRound.roundIndex,
        participantCount: result.data.room.roster.length,
        participants: result.data.room.roster,
      });
      setPhase("result-entry");
    } else {
      setActiveRound(null);
      setPhase("home");
    }
  }, [roomId]);

  useEffect(() => {
    // Standard fetch-on-mount: reload() only sets state after its own
    // internal await resolves, not synchronously in this effect body.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    reload();
  }, [reload]);

  const handleStartGame = async (eventGameId: string) => {
    setBusy(true);
    const result = await startRoomGame(roomId, eventGameId);
    setBusy(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    await reload();
  };

  const handleStartRound = async (eventGameId: string) => {
    setBusy(true);
    const result = await startRound(roomId, eventGameId);
    setBusy(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    setActiveRound(result.data);
    setPhase("result-entry");
  };

  const handleResultConfirmed = async () => {
    // A confirmed result never auto-advances — the coordinator decides
    // the next action (start next round, or finish the game) explicitly.
    await reload();
  };

  const handleFinishGame = async (eventGameId: string) => {
    setBusy(true);
    const result = await completeRoomGame(roomId, eventGameId);
    setBusy(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    const standingsResult = await fetchRoomStandings(roomId);
    if (standingsResult.ok) setStandings(standingsResult.data);
    setPhase("standings-and-next");
  };

  const handleContinueAfterStandings = async () => {
    setStandings(null);
    await reload();
  };

  if (phase === "loading") {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-coord-page">
        <p className="rc-coord-loading">Loading your room…</p>
      </Surface>
    );
  }

  if (phase === "error" && !state) {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-coord-page">
        <p className="rc-coord-error">{error ?? "Something went wrong."}</p>
        <button type="button" className="rc-coord-btn-primary" onClick={reload}>
          Retry
        </button>
      </Surface>
    );
  }

  if (!state) return null;

  if (phase === "standings-and-next" && standings) {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-coord-page">
        <StandingsView roomLabel={roomLabel} standings={standings} onContinue={handleContinueAfterStandings} />
      </Surface>
    );
  }

  if (phase === "result-entry" && activeRound && state.currentGame) {
    return (
      <Surface as="main" ground="night" grain="low" className="rc-coord-page">
        {correctionRoundId ? (
          <CorrectionRequestPanel
            roundId={correctionRoundId}
            snapshot={activeRound}
            scoringTemplate={state.currentGame.scoringTemplate}
            scoringConfig={state.currentGame.scoringConfig}
            onDone={() => {
              setCorrectionRoundId(null);
              reload();
            }}
            onCancel={() => setCorrectionRoundId(null)}
          />
        ) : (
          <ResultEntryFlow
            round={activeRound}
            scoringTemplate={state.currentGame.scoringTemplate}
            scoringConfig={state.currentGame.scoringConfig}
            onConfirmed={handleResultConfirmed}
          />
        )}
      </Surface>
    );
  }

  return (
    <Surface as="main" ground="night" grain="low" className="rc-coord-page">
      <CoordinatorHome
        state={state}
        busy={busy}
        error={error}
        onStartGame={handleStartGame}
        onStartRound={handleStartRound}
        onFinishGame={handleFinishGame}
        onRequestCorrection={(roundId) => {
          setActiveRound({
            roundId,
            roundIndex: state.currentGame?.lastCompletedRound?.roundIndex ?? 0,
            participantCount: state.room.roster.length,
            participants: state.room.roster,
          });
          setCorrectionRoundId(roundId);
          setPhase("result-entry");
        }}
      />
    </Surface>
  );
}

function CoordinatorHome({
  state,
  busy,
  error,
  onStartGame,
  onStartRound,
  onFinishGame,
  onRequestCorrection,
}: {
  state: CoordinatorRoomState;
  busy: boolean;
  error: string | null;
  onStartGame: (eventGameId: string) => void;
  onStartRound: (eventGameId: string) => void;
  onFinishGame: (eventGameId: string) => void;
  onRequestCorrection: (roundId: string) => void;
}) {
  const game = state.currentGame;

  return (
    <>
      <header className="rc-coord-header">
        <p className="rc-coord-room-label rc-numeric">{state.room.label}</p>
        <p className="rc-coord-occupancy">{state.room.occupancy} PLAYERS</p>
      </header>

      {error ? <p className="rc-coord-error">{error}</p> : null}

      {!game ? (
        <section className="rc-coord-card rc-coord-card--done">
          <p className="rc-coord-done-copy">Every configured game is complete for this room.</p>
        </section>
      ) : game.roomGameStatus === "PENDING" ? (
        <section className="rc-coord-card">
          <p className="rc-coord-game-name rc-numeric">{game.gameName}</p>
          <p className="rc-coord-get-ready">GET EVERYONE READY</p>
          <button
            type="button"
            className="rc-coord-btn-primary"
            disabled={busy}
            onClick={() => onStartGame(game.eventGameId)}
          >
            {busy ? "STARTING…" : `START ${game.gameName.toUpperCase()}`}
          </button>
        </section>
      ) : (
        <section className="rc-coord-card">
          <p className="rc-coord-game-name rc-numeric">{game.gameName}</p>
          <p className="rc-coord-round-progress">
            Round {game.completedRounds} of {game.plannedRounds}
          </p>
          <GameTimer startedAt={game.startedAt} durationMinutes={game.durationMinutes} />

          <RoomRoster roster={state.room.roster} />

          {game.lastCompletedRound ? (
            <button
              type="button"
              className="rc-coord-btn-ghost"
              onClick={() => onRequestCorrection(game.lastCompletedRound!.roundId)}
            >
              Something wrong with round {game.lastCompletedRound.roundIndex}? Request correction
            </button>
          ) : null}

          {game.completedRounds < game.plannedRounds ? (
            <button
              type="button"
              className="rc-coord-btn-primary"
              disabled={busy}
              onClick={() => onStartRound(game.eventGameId)}
            >
              {busy ? "STARTING…" : `START ROUND ${game.completedRounds + 1}`}
            </button>
          ) : null}

          <button
            type="button"
            className="rc-coord-btn-secondary"
            disabled={busy}
            onClick={() => onFinishGame(game.eventGameId)}
          >
            {busy ? "FINISHING…" : "FINISH GAME"}
          </button>
          <p className="rc-coord-hint">
            RECESS decides whether this is actually allowed yet — this button may be refused until the round count
            or time window is reached.
          </p>
        </section>
      )}
    </>
  );
}

function RoomRoster({ roster }: { roster: { registrationId: string; alias: string }[] }) {
  return (
    <ul className="rc-coord-roster">
      {roster.map((r) => (
        <li key={r.registrationId} className="rc-coord-roster-chip">
          {r.alias}
        </li>
      ))}
    </ul>
  );
}

function StandingsView({
  roomLabel,
  standings,
  onContinue,
}: {
  roomLabel: string;
  standings: RoomStandingRow[];
  onContinue: () => void;
}) {
  return (
    <>
      <header className="rc-coord-header">
        <p className="rc-coord-room-label rc-numeric">{roomLabel}</p>
        <p className="rc-coord-occupancy">STANDINGS</p>
      </header>
      <ol className="rc-coord-standings">
        {standings.map((row) => (
          <li key={row.registrationId} className="rc-coord-standings-row">
            <span className="rc-coord-standings-placement rc-numeric">{row.placement}</span>
            <span className="rc-coord-standings-alias">{row.alias}</span>
            <span className="rc-coord-standings-points rc-numeric">{row.totalPoints}</span>
            {row.qualifies ? <span className="rc-coord-standings-qualifies">QUALIFIES</span> : null}
          </li>
        ))}
      </ol>
      <button type="button" className="rc-coord-btn-primary" onClick={onContinue}>
        CONTINUE
      </button>
    </>
  );
}
