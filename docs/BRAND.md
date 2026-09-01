# RECESS — Brand & Design System

The supplied RECESS screens are the visual source of truth. This document
explains the system behind them so it can be extended without redesigning it.

## The target

> A genuinely modern event product wearing an expressive independent social
> brand.

Not a retro poster forced into every UI component, and not the brand
reinterpreted as generic modern SaaS.

The test: remove every dice and chess illustration, and RECESS should still be
recognisable through typography, spacing, palette, voice, hierarchy, motion
and interaction. If it isn't, the system hasn't worked.

RECESS is: youthful, social, playful, slightly nostalgic, confident, warm,
imperfect, energetic, modern.

RECESS is not: childish, corporate, cyberpunk, esports, neon-gamer, cartoon
UI, generic SaaS, overly maximalist.

## Tokens

Defined once in `src/styles/tokens.css` as CSS custom properties. Tailwind
consumes them through `tailwind.config.ts`. **The tokens are the source of
truth; Tailwind is the implementation.** If Tailwind were removed tomorrow,
the design system would survive that file intact.

| Token | Value | Role |
|---|---|---|
| `--paper` | `#f4ede0` | cream ground, before the event |
| `--paper-deep` | `#eae0ce` | cards on cream, ticket stock |
| `--ink` | `#1b1219` | type on cream |
| `--ink-soft` | `#5a4a52` | secondary type on cream |
| `--aubergine` | `#24102a` | ground, event night |
| `--aubergine-lift` | `#331a38` | cards on night |
| `--pink` | `#e63368` | primary action, live state — the signature |
| `--pink-deep` | `#c0234f` | pressed state, button shadow |
| `--amber` | `#f0a93c` | secondary accent, focus ring, confetti |

Colours are stored as RGB channel triplets (`--pink-rgb: 230 51 104`) with the
plain variables derived from them, so Tailwind's alpha modifiers (`bg-pink/40`)
work off the same single source.

Two grounds, one accent that works on both. Hot pink on cream is loud; hot
pink on aubergine is luminous.

**Never write a raw hex value in a component.** ESLint blocks it.

## Light and dark are event states, not a toggle

| Moment | Ground |
|---|---|
| Landing, registration | cream — calm anticipation |
| You're in, check-in, live | aubergine — the night has begun |
| Results | aubergine — celebratory |

There is no light/dark mode switch. The product changes because the evening
does. `<Surface ground="paper" | "night">` is the only component allowed to
make that change; everything nested inside reads the semantic `ground` / `fg`
colours and follows automatically.

## Texture

One variable, `--grain`, set by `Surface`. The more operational a screen is,
the cleaner it gets:

```
poster        high
landing       0.12
registration  0.06
event night   0.03
admin         0
```

The brand must survive when the grain disappears.

## Typography

Two families, sharply distinct.

**Display** — heavy, condensed, slightly roughened. Reserved for `RECESS`,
`CHECK IN`, `ROOM 03`, `#024`, `#07`, `YOU'RE IN.`, and large numerals. Set
tight, set large, never below 24px.

**UI** — a clean contemporary sans for forms, tables, admin, metadata,
instructions.

The rule as a token rule: **display type is a token, not a default.** If a
string runs longer than about four words, it is UI type.

Scale: 12 / 14 / 16 / 20 / 28 / 40 / 64 / 96 (`text-rc-xs` through
`text-rc-3xl`). The handover from UI to display sits between 20 and 28.

*Current status:* Anton stands in for the display face and Inter for UI. Anton
is the closest free match to the screens, not the final choice. Swapping it is
one line in `src/app/layout.tsx`.

## White space

**Do not fill empty space simply because it exists.** Game pieces and
illustrations are punctuation, not wallpaper. Objects should feel casually
placed with intentional balance — not a die in every corner creating
artificial symmetry that boxes the content in.

## Illustration

Dice, chess pieces, tickets, pencils, Among Us characters, playful physical
objects. These communicate *play* broadly, not what is being played that
evening.

**Absolutely no game controllers.** A controller icon screams generic gaming
website and RECESS has a far richer visual language.

## Motion

Physical, and spent in one place per screen rather than scattered:

- RECESS letters settle into position; the brushstroke draws underneath.
- A ticket slides in.
- Room assignment shuffles briefly, then lands.
- Points stamp on: `+3`.
- Buttons depress physically — no hover lift, players are on touch.

Avoid bouncing, particle explosions, glowing cyber effects and parallax.
Nothing animates on a coordinator's result screen; that person is in a hurry.
`prefers-reduced-motion` is respected globally in `globals.css`.

## Platform

- **Player: mobile first.** Almost everyone arrives from a WhatsApp link.
- **Admin: desktop first**, responsive.
- **Coordinator: mobile first** — captains are usually playing on another
  device.

**No bottom navigation in the player experience.** RECESS is not a five-tab
app. The event flow is the navigation; use contextual actions and back.

## Quality floor

Responsive to small phones. Visible keyboard focus (amber ring, set globally).
Reduced motion respected. 56px minimum touch targets. Error, loading and empty
states designed rather than defaulted — every important write shows loading,
success, failure and retry.
