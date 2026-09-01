# RECESS — Product

Condensed from the RECESS Product, Brand & Build Bible. Where this file and
the bible disagree, the bible wins and this file gets fixed.

## What RECESS is

**A recurring online social game night.** Gaming is the mechanism, not the
idea.

People spend their weeks working, studying, building, learning, and generally
being consumed by everything they are trying to become. RECESS is deliberately
a break from that. For one evening, people come online, drop the serious
stuff, get thrown into rooms, and play for the sake of playing again.

> RECESS is our night to embrace that inner child and have real fun.

> ALL WORK. NO PLAY...

The name comes from the same emotional territory as school recess: there was
work, then everybody stopped and went to play.

The success test is linguistic. People should say:

> "Are you coming for RECESS on Friday?"

not:

> "Are you participating in the online gaming tournament?"

## What RECESS is not

Not an esports platform. Not Discord with a leaderboard. Not tournament
management software. Not RGB lights, cyberpunk graphics and controllers. Not
childish just because the subject is play. Not a one-off event landing page.

RECESS is a **recurring social ritual with a lightweight competition system
underneath it.** Competition gives the evening structure. The social
experience is the product.

## The night

A person finds RECESS through a poster, a WhatsApp status, or a friend. They
visit the site, see the next date and the games, and tap **I'M IN**. They
register with no account, choose an alias, get a player number, and join the
temporary WhatsApp group.

From then on the website is their **Event Pass**. On the night they check in.
Checked-in players are assigned to rooms. They play several games, some with
multiple rounds, sometimes in parallel rooms. Coordinators submit results.
RECESS calculates points. The leaderboard develops. Everyone reunites for the
finale. Final standings, awards, a champion. Then it ends, the group is
deleted, and next month RECESS happens again.

## Identity

Players have no passwords. Registration collects a real name, a RECESS alias,
and a WhatsApp number.

- **Real identity** is internal: `Alfred Enyinna`
- **RECESS identity** is public: `WH0ISALFRED`

The alias appears on rooms, leaderboards, results, player cards, coordinator
screens and awards. Game-specific aliases map external usernames back to it,
so a coordinator never has to wonder who `Player284` is.

## Everything is configuration

Every edition is an Event. Nothing about September is special.

- Capacity is editable. Thirty was roughly the size of the first one.
- Games come from a permanent library and are reusable. Among Us, Skribbl and
  Trivia are content, not architecture. Monopoly, Ludo, UNO, chess,
  Codenames, GeoGuessr, Gartic Phone or a game that does not exist yet must
  be addable without rewriting anything.
- Scoring uses templates, never per-game logic. There is no
  `if (game === "Among Us")` anywhere.
- Role composition is configuration. RECESS records that a player was an
  impostor. It does not know or care how many impostors there were.

## The scoring philosophy

# Admins record facts. RECESS calculates consequences.

A coordinator says who played, what role they had, and who won. They never
work out that Alfred gets +3 and David gets +3. RECESS knows the
configuration and does it. This is what stops live-event mistakes.

## Two products, two responsibilities

**WhatsApp** is the social layer: announcements, banter, technical problems,
links, screenshots, reactions. It is temporary, created per edition and
deleted afterwards.

**The website** is the source of truth: registration, aliases, check-in,
rooms, rounds, scoring, leaderboard, results, event state.

Do not rebuild WhatsApp inside RECESS.

## What players need from the interface

Players should never need instructions. The interface tells them what matters
*now*.

```
Before the event   Get ready.
At 7:30            Check in.
After check-in     Room 03.
At 8:00            Among Us is live.
After the game     +3 points.
Between games      Next up: Skribbl.
At the end         You finished #7.
```

That is the whole player-facing product.

## What coordinators need

**Reduce thinking during the event.** Nobody wants to operate enterprise
software while everyone is shouting on WhatsApp and trying to start an Among
Us lobby. Large actions, obvious state, minimal typing, preselected rosters,
automatic scoring, clear confirmations, fast next-round creation.

## Voice

Short. Confident. Warm. Occasionally cheeky. Never corporate.

Good: `I'M IN` / `YOU'RE IN.` / `WHAT DO WE CALL YOU?` / `LAST THING.` /
`IT'S RECESS DAY.` / `WELCOME TO ROOM 03` / `YOU'RE LATE 😭` / `NEXT UP` /
`RECESS COMPLETE.`

Bad: `Complete your registration process.` / `Successfully registered!` /
`Participant allocation completed.` / `Embark on an unforgettable gaming
journey.`

Especially avoid AI-sounding inspirational copy.

## The one sentence

**RECESS is not software people are coming to use. RECESS is a night people
are coming to experience — the software should quietly make that night work.**
