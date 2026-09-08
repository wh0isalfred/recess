# RECESS

> All work. No play...

RECESS is a recurring online social game night built around a simple idea: sometimes everyone needs a night to stop working, studying, building and trying to figure life out — and just play.

Players can join with friends or come alone, check in on event night, get assigned to rooms and play through a rotating selection of social games. Results across the night contribute to a shared leaderboard and, eventually, a RECESS champion.

The competition gives the night structure.

The social experience is the point.

## What RECESS does

RECESS provides the infrastructure behind each event:

- Lightweight player registration
- Persistent RECESS aliases
- Event-day check-in
- Dynamic room assignment
- Configurable games and rounds
- Coordinator-led result submission
- Flexible scoring models
- Live event state
- Realtime player updates
- Leaderboards and results
- Event history

RECESS is intentionally not an esports platform or generic tournament manager. It is the digital layer supporting a recurring social experience.

## Product structure

RECESS has three primary experiences:

### Player

Discover → Register → Event Pass → Check In → Join Room → Play → Results

### Coordinator

Access Room → Manage Participants → Run Rounds → Submit Results

### Admin

Manage Event → Roster → Games & Rooms → Live Control → Leaderboard → Results

## Architecture

RECESS is designed around reusable events rather than a single hardcoded game night.

The core domain model is:

Event → Event Games → Rooms → Rounds → Participants → Results → Point Transactions → Leaderboard

Games and scoring rules are configurable so new games can be introduced without adding game-specific logic throughout the application.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the complete technical architecture.

## Tech stack

- Next.js
- TypeScript
- Supabase
- PostgreSQL
- Supabase Realtime
- Tailwind CSS

The implementation prioritizes mobile-first player experiences, reliable live-event operations and server-authoritative scoring.

## Design

RECESS combines a modern digital product with an expressive independent event identity.

The visual system uses warm paper tones, deep aubergine, hot pink and playful supporting colors alongside tactile textures, imperfect marks and game-inspired illustrations.

The product UI deliberately becomes more restrained as screens become more operational.

See [`docs/BRAND.md`](docs/BRAND.md) for the full visual and interaction system.

## Project status

**In development**

The current focus is the first production-ready RECESS event flow:

- [x] Project foundation (Phase 0)
- [ ] Database and domain model
- [ ] Design system
- [ ] Public landing experience
- [ ] Player registration
- [ ] Event Pass
- [ ] Event-day check-in
- [ ] Room assignment
- [ ] Coordinator controls
- [ ] Configurable scoring
- [ ] Live event control
- [ ] Leaderboard
- [ ] Final results

## Development

```bash
git clone https://github.com/wh0isalfred/recess.git
cd recess
npm install
cp .env.example .env.local   # fill in your Supabase URL and anon key
npm run dev
```

Other scripts: `npm run build`, `npm run lint`, `npm run typecheck`.

The design system lives in `src/styles/tokens.css` as CSS custom properties.
Tailwind consumes those tokens; it is not their source of truth. Components
use named utilities (`bg-pink`, `text-fg`, `min-h-tap`) — raw hex values are
blocked by ESLint.

## Contributing

RECESS is built strictly one phase at a time. Read
[`docs/ROADMAP.md`](docs/ROADMAP.md) before starting anything, and
[`CLAUDE.md`](CLAUDE.md) if you are an AI agent.

---

**RECESS**

*Log on. Play.*
