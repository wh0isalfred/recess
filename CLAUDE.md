# CLAUDE.md

Instructions for any AI agent working in this repository. Read this first,
every session.

## The operating rule

**Work on ONE phase at a time.**

Do not begin work belonging to a future phase, even if it seems convenient
while implementing the current one.

At the end of each phase:

1. Run the relevant tests and checks.
2. Verify the acceptance criteria.
3. Summarize exactly what was built.
4. List files and database objects created or changed.
5. State any deviations, unresolved problems, or decisions required.
6. **STOP.**

Wait for explicit approval before beginning the next phase.

Do not use a future phase to hide unfinished work from the current phase.

## Current phase

**Phase 0 — Repository & Project Foundation.** Complete, awaiting review.
Do not start Phase 1 until told.

## Sources of truth

| Question | File |
|---|---|
| What order do we build in? | `docs/ROADMAP.md` |
| Why does RECESS exist, what is it? | `docs/PRODUCT.md` |
| How is it engineered? | `docs/ARCHITECTURE.md` |
| What does it look and sound like? | `docs/BRAND.md` |
| How is the night actually run? | `docs/EVENT-OPS.md` |
| What does a screen look like? | The supplied RECESS screen designs |

The screens are the visual source of truth. `docs/ARCHITECTURE.md` is the
engineering source of truth. Where implementation reveals a conflict between
them, **stop and surface the conflict**. Do not silently choose different
product behaviour.

## Standing rules

- Do not hardcode the September event, three games, two rooms, thirty
  players, or two impostors. All of it is configuration.
- Do not calculate points client-side as the source of truth.
- Do not enforce permissions only in React. Authorization is server-side and
  database-side.
- Do not create player accounts with passwords.
- Do not turn RECESS into a SaaS dashboard.
- Do not add bottom navigation to the player experience.
- Do not use game-controller iconography.
- `src/components` contains no arithmetic. If something computes a point
  value, a rank, or a state decision, it belongs in the database or in
  `src/domain`.
- Brand values live in `src/styles/tokens.css`. Tailwind consumes them.
  Never write an arbitrary value like `bg-[#e63368]` — ESLint blocks raw hex.

## Layout

```
src/app/           routes
src/components/ui/ design system primitives
src/domain/        types, pure logic, no React        (from Phase 1)
src/lib/           env, Supabase clients
src/styles/        tokens
supabase/          migrations and database functions  (from Phase 1)
docs/              the documents above
```
