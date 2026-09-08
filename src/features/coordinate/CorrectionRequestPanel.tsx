"use client";

import { useState } from "react";
import { requestResultCorrection } from "./actions";
import { PlacementInput, RoleOutcomeInput } from "./ResultEntryFlow";
import type { RoleOutcomeAwards, RoundSnapshot, ScoringTemplate } from "./types";

type Phase = "input" | "submitting" | "pending" | "error";

/**
 * The coordinator proposes replacement facts and a reason; nothing
 * authoritative changes here — request_result_correction() only ever
 * creates a PENDING row (migration 0028). Approval is Admin-only and
 * explicitly out of scope for this phase (see EVENT-OPS.md §14: "The
 * coordinator cannot approve their own correction").
 */
export function CorrectionRequestPanel({
  roundId,
  snapshot,
  scoringTemplate,
  scoringConfig,
  onDone,
  onCancel,
}: {
  roundId: string;
  snapshot: RoundSnapshot;
  scoringTemplate: ScoringTemplate;
  scoringConfig: { awards?: RoleOutcomeAwards; type?: string };
  onDone: () => void;
  onCancel: () => void;
}) {
  const [phase, setPhase] = useState<Phase>("input");
  const [dnp, setDnp] = useState<Set<string>>(new Set());
  const [roles, setRoles] = useState<Record<string, string>>({});
  const [winningRole, setWinningRole] = useState<string | null>(null);
  const [scores, setScores] = useState<Record<string, string>>({});
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  const roleKeys = Object.keys(scoringConfig.awards ?? {});
  const isRoleOutcome = scoringTemplate === "ROLE_OUTCOME";

  const buildPayload = () => {
    if (isRoleOutcome) {
      return {
        winningRole,
        participants: snapshot.participants.map((p) => ({
          registrationId: p.registrationId,
          participation: dnp.has(p.registrationId) ? "DNP" : "PARTICIPATING",
          role: dnp.has(p.registrationId) ? null : (roles[p.registrationId] ?? roleKeys[0] ?? null),
        })),
      };
    }
    return {
      scores: snapshot.participants.map((p) => ({
        registrationId: p.registrationId,
        participation: dnp.has(p.registrationId) ? "DNP" : "PARTICIPATING",
        ...(dnp.has(p.registrationId) ? {} : { rawScore: Number(scores[p.registrationId] ?? 0) }),
      })),
    };
  };

  const canSubmit = reason.trim() !== "" && (isRoleOutcome ? winningRole !== null : true);

  const handleSubmit = async () => {
    setPhase("submitting");
    setError(null);
    const result = await requestResultCorrection(roundId, buildPayload(), reason.trim());
    if (!result.ok) {
      setError(result.message);
      setPhase("error");
      return;
    }
    setPhase("pending");
  };

  if (phase === "pending") {
    return (
      <section className="rc-coord-card">
        <p className="rc-coord-pending">PENDING ADMIN REVIEW</p>
        <p className="rc-coord-hint">
          Your correction request has been sent. An Admin will review it — you can&rsquo;t approve your own
          correction.
        </p>
        <button type="button" className="rc-coord-btn-primary" onClick={onDone}>
          BACK TO ROOM
        </button>
      </section>
    );
  }

  return (
    <section className="rc-coord-card">
      <h2 className="rc-coord-preview-title">REQUEST CORRECTION</h2>
      <p className="rc-coord-hint">Round {snapshot.roundIndex} — enter what actually happened.</p>
      {error ? <p className="rc-coord-error">{error}</p> : null}

      {isRoleOutcome ? (
        <RoleOutcomeInput
          participants={snapshot.participants}
          roleKeys={roleKeys}
          dnp={dnp}
          setDnp={setDnp}
          roles={roles}
          setRoles={setRoles}
          winningRole={winningRole}
          setWinningRole={setWinningRole}
        />
      ) : (
        <PlacementInput participants={snapshot.participants} dnp={dnp} setDnp={setDnp} scores={scores} setScores={setScores} />
      )}

      <label className="rc-coord-reason-field">
        <span>Why is the confirmed result wrong?</span>
        <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} placeholder="Reason RECESS will show the Admin" />
      </label>

      <div className="rc-coord-preview-actions">
        <button type="button" className="rc-coord-btn-ghost" onClick={onCancel}>
          CANCEL
        </button>
        <button type="button" className="rc-coord-btn-primary" disabled={!canSubmit || phase === "submitting"} onClick={handleSubmit}>
          {phase === "submitting" ? "SENDING…" : "SEND CORRECTION REQUEST"}
        </button>
      </div>
    </section>
  );
}
