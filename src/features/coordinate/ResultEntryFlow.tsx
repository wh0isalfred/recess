"use client";

import { useMemo, useState } from "react";
import { previewRoundResult, submitRoundResult } from "./actions";
import type { ResultPreview, RoleOutcomeAwards, RoundSnapshot, ScoringTemplate } from "./types";

type SubmitPhase = "input" | "preview" | "submitting" | "confirmed" | "not-sent";

export function ResultEntryFlow({
  round,
  scoringTemplate,
  scoringConfig,
  onConfirmed,
}: {
  round: RoundSnapshot;
  scoringTemplate: ScoringTemplate;
  scoringConfig: { awards?: RoleOutcomeAwards; type?: string };
  onConfirmed: () => void;
}) {
  const [phase, setPhase] = useState<SubmitPhase>("input");
  const [dnp, setDnp] = useState<Set<string>>(new Set());
  const [roles, setRoles] = useState<Record<string, string>>({});
  const [winningRole, setWinningRole] = useState<string | null>(null);
  const [scores, setScores] = useState<Record<string, string>>({});
  const [preview, setPreview] = useState<ResultPreview | null>(null);
  const [error, setError] = useState<string | null>(null);
  // One key per confirmation attempt, generated once and reused for every
  // retry of THIS result — never regenerated on a Retry press. Phase 7's
  // idempotency guarantee only holds if the client keeps its half of the
  // contract.
  const [idempotencyKey] = useState(() => crypto.randomUUID());

  const roleKeys = useMemo(() => Object.keys(scoringConfig.awards ?? {}), [scoringConfig]);
  const isRoleOutcome = scoringTemplate === "ROLE_OUTCOME";

  const buildPayload = () => {
    if (isRoleOutcome) {
      return {
        winningRole,
        participants: round.participants.map((p) => ({
          registrationId: p.registrationId,
          participation: dnp.has(p.registrationId) ? "DNP" : "PARTICIPATING",
          role: dnp.has(p.registrationId) ? null : (roles[p.registrationId] ?? roleKeys[0] ?? null),
        })),
      };
    }
    return {
      scores: round.participants.map((p) => ({
        registrationId: p.registrationId,
        participation: dnp.has(p.registrationId) ? "DNP" : "PARTICIPATING",
        ...(dnp.has(p.registrationId) ? {} : { rawScore: Number(scores[p.registrationId] ?? 0) }),
      })),
    };
  };

  const canPreview = isRoleOutcome
    ? winningRole !== null && round.participants.every((p) => dnp.has(p.registrationId) || roles[p.registrationId])
    : round.participants.every((p) => dnp.has(p.registrationId) || scores[p.registrationId]?.trim());

  const handlePreview = async () => {
    setError(null);
    const result = await previewRoundResult(round.roundId, buildPayload());
    if (!result.ok) {
      setError(result.message);
      return;
    }
    setPreview(result.data);
    setPhase("preview");
  };

  const handleConfirm = async () => {
    setPhase("submitting");
    setError(null);
    const result = await submitRoundResult(round.roundId, buildPayload(), idempotencyKey);
    if (!result.ok) {
      setError(result.message);
      setPhase("not-sent");
      return;
    }
    setPhase("confirmed");
  };

  if (phase === "confirmed") {
    return (
      <section className="rc-coord-card">
        <p className="rc-coord-confirmed">RESULT CONFIRMED</p>
        <button type="button" className="rc-coord-btn-primary" onClick={onConfirmed}>
          CONTINUE
        </button>
      </section>
    );
  }

  if (phase === "submitting") {
    return (
      <section className="rc-coord-card">
        <p className="rc-coord-submitting">SUBMITTING…</p>
      </section>
    );
  }

  if (phase === "not-sent") {
    return (
      <section className="rc-coord-card">
        <p className="rc-coord-not-sent">NOT SENT</p>
        <p className="rc-coord-not-sent-copy">Result was not confirmed.{error ? ` ${error}` : ""}</p>
        <button type="button" className="rc-coord-btn-primary" onClick={handleConfirm}>
          RETRY
        </button>
      </section>
    );
  }

  if (phase === "preview" && preview) {
    return (
      <section className="rc-coord-card">
        <h2 className="rc-coord-preview-title">CONFIRM RESULT</h2>
        <p className="rc-coord-hint">Round {round.roundIndex} — check this is right before confirming.</p>
        {isRoleOutcome ? <p className="rc-coord-preview-winner">{winningRole?.toUpperCase()}S WON</p> : null}
        <ul className="rc-coord-preview-list">
          {preview.facts.map((f) => (
            <li key={f.registrationId} className="rc-coord-preview-row">
              <span className="rc-coord-preview-alias">{f.alias}</span>
              <span className="rc-coord-preview-fact">
                {f.participation === "DNP" ? "DNP" : isRoleOutcome ? f.role?.toUpperCase() : f.rawScore}
              </span>
            </li>
          ))}
        </ul>
        {error ? <p className="rc-coord-error">{error}</p> : null}
        <div className="rc-coord-preview-actions">
          <button type="button" className="rc-coord-btn-ghost" onClick={() => setPhase("input")}>
            BACK
          </button>
          <button type="button" className="rc-coord-btn-primary" onClick={handleConfirm}>
            CONFIRM
          </button>
        </div>
      </section>
    );
  }

  return (
    <section className="rc-coord-card">
      <h2 className="rc-coord-preview-title">ROUND {round.roundIndex}</h2>
      {error ? <p className="rc-coord-error">{error}</p> : null}

      {isRoleOutcome ? (
        <RoleOutcomeInput
          participants={round.participants}
          roleKeys={roleKeys}
          dnp={dnp}
          setDnp={setDnp}
          roles={roles}
          setRoles={setRoles}
          winningRole={winningRole}
          setWinningRole={setWinningRole}
        />
      ) : (
        <PlacementInput participants={round.participants} dnp={dnp} setDnp={setDnp} scores={scores} setScores={setScores} />
      )}

      <button type="button" className="rc-coord-btn-primary" disabled={!canPreview} onClick={handlePreview}>
        PREVIEW RESULT
      </button>
    </section>
  );
}

export function RoleOutcomeInput({
  participants,
  roleKeys,
  dnp,
  setDnp,
  roles,
  setRoles,
  winningRole,
  setWinningRole,
}: {
  participants: { registrationId: string; alias: string }[];
  roleKeys: string[];
  dnp: Set<string>;
  setDnp: (s: Set<string>) => void;
  roles: Record<string, string>;
  setRoles: (r: Record<string, string>) => void;
  winningRole: string | null;
  setWinningRole: (r: string) => void;
}) {
  // The fast two-role UX the brief shows ("WHO WERE THE IMPOSTORS?") only
  // makes sense when the game is configured with exactly two roles — the
  // non-marked role is the natural default for everyone else. With any
  // other configured role count, each participant gets an explicit picker
  // instead, so the recorded facts stay correct regardless of
  // configuration; nothing here hardcodes CREWMATE/IMPOSTOR.
  const secondaryRole = roleKeys.length === 2 ? roleKeys[1] : null;
  const primaryRole = roleKeys.length === 2 ? roleKeys[0] : null;

  const toggleDnp = (registrationId: string) => {
    const next = new Set(dnp);
    if (next.has(registrationId)) next.delete(registrationId);
    else next.add(registrationId);
    setDnp(next);
  };

  const toggleSecondaryRole = (registrationId: string, checked: boolean) => {
    setRoles({ ...roles, [registrationId]: checked ? secondaryRole! : primaryRole! });
  };

  return (
    <>
      {secondaryRole && primaryRole ? (
        <fieldset className="rc-coord-field-group">
          <legend className="rc-coord-field-legend">WHO WERE THE {secondaryRole.toUpperCase()}S?</legend>
          {participants.map((p) => (
            <label key={p.registrationId} className={`rc-coord-check-row ${dnp.has(p.registrationId) ? "rc-coord-check-row--dnp" : ""}`}>
              <input
                type="checkbox"
                disabled={dnp.has(p.registrationId)}
                checked={roles[p.registrationId] === secondaryRole}
                onChange={(e) => toggleSecondaryRole(p.registrationId, e.target.checked)}
              />
              <span>{p.alias}</span>
              <button
                type="button"
                className="rc-coord-dnp-toggle"
                onClick={(e) => {
                  e.preventDefault();
                  toggleDnp(p.registrationId);
                }}
              >
                {dnp.has(p.registrationId) ? "DNP" : "mark DNP"}
              </button>
            </label>
          ))}
        </fieldset>
      ) : (
        <fieldset className="rc-coord-field-group">
          <legend className="rc-coord-field-legend">ROLES</legend>
          {participants.map((p) => (
            <div key={p.registrationId} className="rc-coord-role-row">
              <span>{p.alias}</span>
              {dnp.has(p.registrationId) ? (
                <span className="rc-coord-dnp-label">DNP</span>
              ) : (
                <select value={roles[p.registrationId] ?? ""} onChange={(e) => setRoles({ ...roles, [p.registrationId]: e.target.value })}>
                  <option value="" disabled>
                    choose role
                  </option>
                  {roleKeys.map((r) => (
                    <option key={r} value={r}>
                      {r.toUpperCase()}
                    </option>
                  ))}
                </select>
              )}
              <button type="button" className="rc-coord-dnp-toggle" onClick={() => toggleDnp(p.registrationId)}>
                {dnp.has(p.registrationId) ? "undo DNP" : "mark DNP"}
              </button>
            </div>
          ))}
        </fieldset>
      )}

      <fieldset className="rc-coord-field-group">
        <legend className="rc-coord-field-legend">WHO WON?</legend>
        <div className="rc-coord-winner-toggle">
          {roleKeys.map((r) => (
            <button
              key={r}
              type="button"
              className={`rc-coord-winner-btn ${winningRole === r ? "rc-coord-winner-btn--active" : ""}`}
              onClick={() => setWinningRole(r)}
            >
              {r.toUpperCase()}S
            </button>
          ))}
        </div>
      </fieldset>
    </>
  );
}

export function PlacementInput({
  participants,
  dnp,
  setDnp,
  scores,
  setScores,
}: {
  participants: { registrationId: string; alias: string }[];
  dnp: Set<string>;
  setDnp: (s: Set<string>) => void;
  scores: Record<string, string>;
  setScores: (s: Record<string, string>) => void;
}) {
  const toggleDnp = (registrationId: string) => {
    const next = new Set(dnp);
    if (next.has(registrationId)) next.delete(registrationId);
    else next.add(registrationId);
    setDnp(next);
  };

  return (
    <fieldset className="rc-coord-field-group">
      <legend className="rc-coord-field-legend">RAW SCORES</legend>
      {participants.map((p) => (
        <div key={p.registrationId} className="rc-coord-score-row">
          <span>{p.alias}</span>
          {dnp.has(p.registrationId) ? (
            <span className="rc-coord-dnp-label">DNP</span>
          ) : (
            <input
              type="number"
              inputMode="numeric"
              min={0}
              value={scores[p.registrationId] ?? ""}
              onChange={(e) => setScores({ ...scores, [p.registrationId]: e.target.value })}
              placeholder="score"
            />
          )}
          <button type="button" className="rc-coord-dnp-toggle" onClick={() => toggleDnp(p.registrationId)}>
            {dnp.has(p.registrationId) ? "undo DNP" : "mark DNP"}
          </button>
        </div>
      ))}
    </fieldset>
  );
}
