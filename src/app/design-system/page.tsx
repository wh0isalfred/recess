import { notFound } from "next/navigation";
import {
  Surface,
  Panel,
  Button,
  Field,
  StatusBadge,
  PlayerChip,
  GameTile,
  RoomCard,
  EventCard,
  ProgressIndicator,
  ScoreDisplay,
  LeaderboardRow,
  Ticket,
} from "@/components";
import { Section, Row, Phone } from "./Specimen";

/**
 * The RECESS design-system lab.
 *
 * Development only — this route 404s in a production build. It exists so the
 * system can be judged in realistic combinations before any real screen is
 * built on top of it. It is deliberately not a landing page.
 */
export const dynamic = "force-static";

const PALETTE: { name: string; token: string; note: string }[] = [
  { name: "paper", token: "--paper", note: "ground before the event" },
  { name: "paper-deep", token: "--paper-deep", note: "panels, ticket stock" },
  { name: "ink", token: "--ink", note: "15.7:1 on paper" },
  { name: "ink-soft", token: "--ink-soft", note: "7.1:1 on paper" },
  { name: "aubergine", token: "--aubergine", note: "ground on event night" },
  { name: "aubergine-lift", token: "--aubergine-lift", note: "panels on night" },
  { name: "pink", token: "--pink", note: "fills and display type" },
  { name: "pink-deep", token: "--pink-deep", note: "offset, 5.0:1 on paper" },
  { name: "pink-lift", token: "--pink-lift", note: "6.7:1 on aubergine" },
  { name: "amber", token: "--amber", note: "focus ring — never text on cream" },
  { name: "cobalt", token: "--cobalt", note: "7.4:1 on paper" },
  { name: "cobalt-lift", token: "--cobalt-lift", note: "6.7:1 on aubergine" },
];

const TYPE_SCALE = [
  { cls: "text-rc-3xl", label: "96 · display", sample: "RECESS" },
  { cls: "text-rc-2xl", label: "64 · display", sample: "024" },
  { cls: "text-rc-xl", label: "40 · display", sample: "CHECK IN" },
  { cls: "text-rc-lg", label: "28 · display", sample: "Room 03" },
];

export default function DesignSystemPage() {
  if (process.env.NODE_ENV === "production") notFound();

  return (
    <main className="min-h-dvh bg-neutral-100 pb-24 text-neutral-900">
      <header className="mx-auto max-w-5xl px-6 pt-16 pb-4">
        <p className="font-mono text-xs text-neutral-500">
          development only · not a product screen
        </p>
        <h1 className="mt-3 font-display text-4xl">RECESS design system</h1>
        <p className="mt-3 max-w-[62ch] text-sm text-neutral-600">
          Roughly 80% quiet product interface, 20% RECESS. The brand is spent
          on arrival, confirmation, room reveal and results; utility screens
          stay calm. Two rules run through everything below: colour follows
          the ground rather than a theme toggle, and depth is a hard offset
          rather than a blur.
        </p>
      </header>

      {/* ------------------------------------------------------- palette */}
      <Section
        title="Palette"
        note="Two grounds, one accent that works on both. Semantic colours are redefined per ground so each clears 4.5:1 wherever it lands. Ratios below are measured, not estimated."
      >
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          {PALETTE.map((c) => (
            <div key={c.name}>
              <div
                className="h-16 rounded border border-neutral-300"
                style={{ background: `var(${c.token})` }}
              />
              <p className="mt-2 font-mono text-xs">{c.name}</p>
              <p className="text-xs text-neutral-500">{c.note}</p>
            </div>
          ))}
        </div>

        <Row caption="the same three state colours, on each ground" cols="two">
          {(["paper", "night"] as const).map((g) => (
            <Surface key={g} ground={g} grain="low" className="rounded-lg p-6">
              <div className="relative z-10 flex flex-wrap gap-2">
                <StatusBadge tone="live" pulse>Live now</StatusBadge>
                <StatusBadge tone="confirmed">Checked in</StatusBadge>
                <StatusBadge tone="waiting">Waiting for a room</StatusBadge>
                <StatusBadge tone="inactive">Did not play</StatusBadge>
                <StatusBadge tone="info">Registration open</StatusBadge>
              </div>
            </Surface>
          ))}
        </Row>
      </Section>

      {/* ---------------------------------------------------- typography */}
      <Section
        title="Typography"
        note="Archivo Black for the poster voice, Archivo for everything a person has to read. One superfamily, so the interface reads as one voice. Caps belong to emotional moments; utility copy is sentence case."
      >
        <Surface ground="paper" grain="mid" className="rounded-lg p-8">
          <div className="relative z-10 space-y-6">
            {TYPE_SCALE.map((t) => (
              <div key={t.cls} className="flex flex-wrap items-baseline gap-6">
                <span className="w-28 shrink-0 font-mono text-xs text-ink-soft">
                  {t.label}
                </span>
                <span className={`font-display ${t.cls}`}>{t.sample}</span>
              </div>
            ))}

            <div className="flex flex-wrap items-baseline gap-6 border-t-[length:var(--hairline)] border-fg-line pt-6">
              <span className="w-28 shrink-0 font-mono text-xs text-ink-soft">
                20 · ui
              </span>
              <p className="max-w-[46ch] text-rc-md">
                Room assignments are revealed after check-in.
              </p>
            </div>
            <div className="flex flex-wrap items-baseline gap-6">
              <span className="w-28 shrink-0 font-mono text-xs text-ink-soft">
                16 · ui
              </span>
              <p className="max-w-[62ch] text-rc-base">
                RECESS is our night to embrace that inner child and have real
                fun. Come solo or bring your people — you will be put in a room
                either way.
              </p>
            </div>
            <div className="flex flex-wrap items-baseline gap-6">
              <span className="w-28 shrink-0 font-mono text-xs text-ink-soft">
                12 · label
              </span>
              <p className="rc-label">Player number</p>
            </div>
          </div>
        </Surface>
      </Section>

      {/* -------------------------------------------------------- buttons */}
      <Section
        title="Buttons"
        note="The primary control sits on a hard pink offset that collapses under the thumb. No hover lift: players are on touch screens. Every write in RECESS has a loading state, because a coordinator on bad mobile data must never wonder whether a tap landed."
      >
        <Row cols="two">
          {(["paper", "night"] as const).map((g) => (
            <Surface key={g} ground={g} grain="low" className="rounded-lg p-6">
              <div className="relative z-10 flex flex-col gap-3">
                <Button variant="primary" arrow>I&rsquo;m in</Button>
                <Button variant="secondary">Add to calendar</Button>
                <Button variant="primary" loading loadingLabel="Checking you in" >Check in</Button>
                <Button variant="primary" disabled>RECESS is full</Button>
                <Button variant="danger" size="sm">Void this round</Button>
                <Button variant="ghost">Back</Button>
              </div>
            </Surface>
          ))}
        </Row>
      </Section>

      {/* --------------------------------------------------------- fields */}
      <Section
        title="Fields"
        note="One input, one label, one message. Error and success carry a glyph and words as well as a colour, and the border changes with them."
      >
        <Row cols="two">
          <Surface ground="paper" grain="low" className="rounded-lg p-6">
            <div className="relative z-10 space-y-6">
              <Field id="ds-name" label="What's your name?" defaultValue="Alfred Enyinna" />
              <Field
                id="ds-alias"
                label="What do we call you?"
                hint="This is the name everyone else sees all night."
                defaultValue="WH0ISALFRED"
                success="That one's free."
              />
              <Field
                id="ds-alias-taken"
                label="What do we call you?"
                defaultValue="WH0ISALFRED"
                error="Someone already took that for this RECESS."
              />
            </div>
          </Surface>
          <Surface ground="night" grain="low" className="rounded-lg p-6">
            <div className="relative z-10 space-y-6">
              <Field
                id="ds-phone"
                label="WhatsApp number"
                hint="Only used for RECESS updates and the event group."
                prefix="+234"
                inputMode="tel"
                defaultValue="801 234 5678"
              />
              <Field id="ds-among" label="Your Among Us name" defaultValue="alfred2009" />
              <Field id="ds-empty" label="Your Skribbl name" placeholder="Type it exactly as it appears" />
            </div>
          </Surface>
        </Row>
      </Section>

      {/* ---------------------------------------------------- composition */}
      <Section
        title="In situ · player, mobile"
        note="Fragments at 390px, the width almost every player arrives at from a WhatsApp link. These are specimens, not screens — Phase 3 onwards decides what a page actually contains."
      >
        <Row>
          <Phone caption="before the night · cream, calm">
            <Surface ground="paper" grain="high" className="p-6">
              <div className="relative z-10 space-y-6">
                <EventCard
                  name="RECESS — September"
                  weekday="Fri"
                  date="11 Sept"
                  time="8:00 PM"
                  timezone="WAT"
                  daysToGo={3}
                  status="You're in"
                  registered="42 registered · 18 spots left"
                />
                <div>
                  <p className="rc-label mb-1">Get ready</p>
                  <GameTile name="Skribbl" platform="BROWSER" position={1} />
                  <GameTile name="Among Us" platform="INSTALL" rounds={4} position={2} />
                  <GameTile name="Trivia" platform="BROWSER" position={3} />
                </div>
                <Button variant="primary" arrow>Join the WhatsApp group</Button>
              </div>
            </Surface>
          </Phone>

          <Phone caption="arrival · the ticket, the one loud object">
            <Surface ground="night" grain="low" className="p-6">
              <div className="relative z-10 space-y-6 text-center">
                <h2 className="font-display text-rc-xl">YOU&rsquo;RE IN.</h2>
                <p className="font-display text-rc-md text-accent-text">WH0ISALFRED</p>
                <div className="flex justify-center">
                  <Ticket label="Player number" value="024" footnote="Friday 11 Sept · 8:00 PM WAT" />
                </div>
                <Button variant="primary" arrow>Join the WhatsApp group</Button>
                <Button variant="ghost">Add to calendar</Button>
              </div>
            </Surface>
          </Phone>

          <Phone caption="live · quiet, because the game is elsewhere">
            <Surface ground="night" grain="low" className="p-6">
              <div className="relative z-10 space-y-6">
                <div>
                  <p className="rc-label">Welcome to</p>
                  <h2 className="font-display text-rc-xl text-accent-text">ROOM 03</h2>
                  <div className="mt-2">
                    <StatusBadge tone="confirmed">Checked in</StatusBadge>
                  </div>
                </div>
                <Panel className="space-y-4 p-4">
                  <div className="flex items-center justify-between">
                    <span className="font-display text-rc-md">Among Us</span>
                    <StatusBadge tone="live" pulse>Live now</StatusBadge>
                  </div>
                  <ProgressIndicator variant="rounds" current={1} total={4} />
                </Panel>
                <div className="flex gap-8">
                  <ScoreDisplay label="Your position" value={12} prefix="#" />
                  <ScoreDisplay label="Points" value={8} delta={3} tone="accent" />
                </div>
              </div>
            </Surface>
          </Phone>

          <Phone caption="results · celebratory, and the ticket returns">
            <Surface ground="night" grain="low" className="p-6">
              <div className="relative z-10 space-y-6">
                <h2 className="text-center font-display text-rc-lg text-accent-text">
                  RECESS COMPLETE
                </h2>
                <div className="flex justify-center">
                  <Ticket label="You finished" value="07" />
                </div>
                <ul className="mt-2">
                  <LeaderboardRow position={1} alias="ACE" points={58} breakdown="Skribbl +10 · Among Us +34 · Trivia +14" />
                  <LeaderboardRow position={2} alias="DAVO" points={52} />
                  <LeaderboardRow position={2} alias="KAY" points={52} tied />
                  <LeaderboardRow position={4} alias="MIMI" points={47} />
                  <LeaderboardRow position={7} alias="WH0ISALFRED" points={42} isSelf />
                </ul>
              </div>
            </Surface>
          </Phone>
        </Row>
      </Section>

      {/* -------------------------------------------------- rooms/players */}
      <Section
        title="Rooms and players"
        note="Room cards carry occupancy as a fraction and a bar, because sequential fill makes 'how close to full' the number that matters. A missing WhatsApp link shows as a warning, never as a blocker."
      >
        <Row cols="two">
          <Surface ground="paper" grain="none" className="rounded-lg p-6">
            <div className="relative z-10 grid gap-4 sm:grid-cols-2">
              <RoomCard label="Room 01" occupied={15} capacity={15} coordinator="KAY" state="full" />
              <RoomCard label="Room 02" occupied={9} capacity={15} coordinator="DAVO" state="filling" hasWhatsApp={false} />
              <RoomCard label="Room 03" occupied={0} capacity={15} state="empty" />
              <RoomCard label="Room 04" occupied={13} capacity={15} coordinator="MIMI" state="live" />
            </div>
          </Surface>

          <Surface ground="night" grain="low" className="rounded-lg p-6">
            <div className="relative z-10 space-y-5">
              <RoomCard label="Room 03" occupied={13} capacity={15} coordinator="MIMI" state="live" emphasis />
              <Panel className="space-y-4 p-4">
                <p className="rc-label">Roster · Among Us round 3</p>
                <PlayerChip alias="ACE" playerNumber={7} gameAlias="ace_ng" status="Playing" />
                <PlayerChip alias="DAVO" playerNumber={12} gameAlias="Davo" status="Impostor" statusTone="live" />
                <PlayerChip alias="WH0ISALFRED" playerNumber={24} gameAlias="alfred2009" status="Playing" />
                <PlayerChip alias="JAY" playerNumber={31} status="Did not play" statusTone="inactive" />
              </Panel>
            </div>
          </Surface>
        </Row>
      </Section>

      {/* ------------------------------------------------- progress/score */}
      <Section
        title="Progress and numbers"
        note="Numerals are tabular everywhere a number is compared to another number. Ties read 1, 2, 2, 4 with an equals sign, because two people sharing second place is a result rather than a rendering problem."
      >
        <Row cols="two">
          <Surface ground="paper" grain="low" className="rounded-lg p-6">
            <div className="relative z-10 space-y-8">
              <ProgressIndicator current={2} total={3} />
              <ProgressIndicator variant="rounds" current={3} total={4} label="Among Us" />
              <div className="flex gap-8">
                <ScoreDisplay label="Days to go" value="03" size="lg" tone="accent" />
                <ScoreDisplay label="Finished" value={7} prefix="#" size="lg" />
              </div>
            </div>
          </Surface>
          <Surface ground="night" grain="low" className="rounded-lg p-6">
            <div className="relative z-10">
              <p className="rc-label mb-2">Standings · between games</p>
              <ul>
                <LeaderboardRow position={1} alias="ACE" points={31} />
                <LeaderboardRow position={2} alias="KAY" points={28} />
                <LeaderboardRow position={2} alias="DAVO" points={28} tied />
                <LeaderboardRow position={4} alias="WH0ISALFRED" points={24} isSelf breakdown="Skribbl +7 · Among Us R1 +4 · R2 +0" />
              </ul>
            </div>
          </Surface>
        </Row>
      </Section>

      {/* ---------------------------------------------------- edge states */}
      <Section
        title="Empty, waiting and failed"
        note="An empty screen is an invitation to act, and a failure says what happened and what to do next. Neither apologises, and neither relies on colour to carry the meaning."
      >
        <Row cols="two">
          <Surface ground="night" grain="low" className="rounded-lg p-6">
            <Panel className="relative z-10 space-y-3 p-6 text-center">
              <StatusBadge tone="waiting">Waiting for a room</StatusBadge>
              <p className="text-rc-base text-fg-soft">
                Every room is full right now. You&rsquo;ll be placed in the next
                game that has space — stay in the group chat.
              </p>
            </Panel>
          </Surface>

          <Surface ground="paper" grain="low" className="rounded-lg p-6">
            <Panel className="relative z-10 space-y-4 p-6">
              <p className="flex items-center gap-2 font-display text-rc-md text-alert">
                <span aria-hidden="true">✕</span> Result didn&rsquo;t send
              </p>
              <p className="text-rc-base text-fg-soft">
                Your connection dropped. Nothing was scored, and tapping again
                won&rsquo;t double anyone&rsquo;s points.
              </p>
              <Button variant="secondary" size="sm">Try again</Button>
            </Panel>
          </Surface>
        </Row>
      </Section>

      {/* ------------------------------------------------------ admin */}
      <Section
        title="In situ · admin, desktop"
        note="The same components at desktop width, with grain off entirely. Admin is the most operational surface in RECESS, so it is the cleanest: same palette, same type, almost no texture."
      >
        <Surface ground="paper" grain="none" className="rounded-lg p-8">
          <div className="relative z-10 space-y-6">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div>
                <p className="rc-label">Live control</p>
                <h3 className="font-display text-rc-lg">RECESS — September</h3>
              </div>
              <div className="flex gap-3">
                <Button variant="secondary" size="sm">Pause event</Button>
                <Button variant="primary" size="sm" arrow>Start next game</Button>
              </div>
            </div>
            <div className="grid gap-4 md:grid-cols-3">
              <RoomCard label="Room 01" occupied={15} capacity={15} coordinator="KAY" state="live" />
              <RoomCard label="Room 02" occupied={12} capacity={15} coordinator="DAVO" state="live" hasWhatsApp={false} />
              <RoomCard label="Room 03" occupied={11} capacity={15} state="filling" />
            </div>
          </div>
        </Surface>
      </Section>
    </main>
  );
}