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
consumes them through the `@theme inline` block in `src/app/globals.css`.
**The tokens are the source of
truth; Tailwind is the implementation.** If Tailwind were removed tomorrow,
the design system would survive that file intact.

| Token | Value | Role | Contrast |
|---|---|---|---|
| `--paper` | `#f4ede0` | cream ground, before the event | — |
| `--paper-deep` | `#eae0ce` | panels on cream, ticket stock | — |
| `--ink` | `#1b1219` | type on cream | 15.7:1 |
| `--ink-soft` | `#5a4a52` | secondary type on cream | 7.1:1 |
| `--aubergine` | `#24102a` | ground, event night | — |
| `--aubergine-lift` | `#331a38` | panels on night | — |
| `--pink` | `#e63368` | fills and display type — the signature | 3.6:1 |
| `--pink-deep` | `#c0234f` | pressed state, hard offset, accent text on cream | 5.0:1 |
| `--pink-lift` | `#ff6f93` | accent text on night | 6.7:1 |
| `--amber` | `#f0a93c` | focus ring, confetti | 1.7:1 on cream |
| `--amber-deep` | `#8a5200` | amber when it must be legible on cream | 5.5:1 |
| `--cobalt` | `#2438c4` | structural accent on cream | 7.4:1 |
| `--cobalt-lift` | `#8b96ff` | structural accent on night | 6.7:1 |



Ratios are measured, not estimated. Two of them constrain usage and must be
respected:

- **`--pink` is a fill, not body text.** At 3.6:1 on cream it clears WCAG only
  as large text, so pink type is display-scale or it is `--accent-text`
  instead, which resolves to `--pink-deep` on cream and `--pink-lift` on night.
- **`--amber` is never text on cream.** At 1.7:1 it is a ring, a dot or a
  confetti fragment, and the meaning is always carried by a word or a glyph
  beside it.

### State colours

`--go`, `--warn`, `--alert` and `--info` are **redefined per ground** rather
than fixed, so each clears 4.5:1 wherever it lands. A component writes
`text-go` and gets the right value on cream and on aubergine without knowing
which one it is on.

### Depth is offset, never blur

There is not one soft grey shadow in this system. Panels sit flat on the
ground with a hairline border; controls sit on a hard coloured offset that
collapses under the thumb. Print, not glass. `--lift-control` and
`--lift-paper` are the only two depth tokens, and both are zero-blur.

### Radius encodes role

`--r-control` 8px for things you touch, `--r-surface` 4px for printed panels,
`--r-pill` for chips only, `--r-ticket` 3px because the ticket is die-cut
instead. Paper does not have rounded corners; controls do.
Every translucent value is a named token too — `--fg-line`, `--fg-muted`,
`--field-fill` — rather than an alpha modifier written at each call site. One
hairline colour defined once beats 20% here and 15% three files away. Because
those tints are built from `--fg`, they follow the active Surface as well.

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

**Archivo Black for display, Archivo for UI.** One superfamily in two roles:
they share a skeleton, so the interface reads as one voice rather than a
display face arguing with a body face. RECESS gets its personality from scale,
colour and paper, which leaves the typography free to be disciplined. Archivo
Black is also closer to the poster wordmark's width than a condensed face
would be.

**Caps belong to emotional moments.** `I'M IN`, `CHECK IN`, `YOU'RE IN.`,
`ROOM 03` are set in caps because that is the brand's voice at the moments it
speaks up. Utility copy — hints, errors, empty states, admin tables — is
sentence case. This is the 80/20 rule applied to typography rather than a
blanket style.

**Numerals are tabular** wherever a number is compared to another number:
leaderboards, scores, player numbers, countdowns. The `.rc-numeric` class.

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
