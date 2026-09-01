import { Surface } from "@/components/ui/Surface";
import { Button } from "@/components/ui/Button";
import { Field } from "@/components/ui/Field";

/**
 * PHASE 0 FOUNDATION CHECK — not a product screen.
 *
 * Exists only to satisfy the Phase 0 acceptance criterion that cream and
 * aubergine Surface examples render correctly. Phase 3 replaces this file
 * entirely with the public landing experience.
 */
export default function FoundationCheck() {
  return (
    <>
      <Surface as="main" ground="paper" grain="high" className="px-6 py-10">
        <div className="relative z-10 mx-auto flex max-w-md flex-col gap-8">
          <header className="flex flex-col gap-2">
            <p className="text-rc-xs tracking-[0.14em] text-fg-soft">
              PHASE 0 &middot; FOUNDATION CHECK
            </p>
            <h1 className="font-display text-rc-2xl">RECESS</h1>
            <p className="max-w-[32ch] text-rc-base text-fg-soft">
              Paper surface. This page is scaffolding and gets replaced by the
              landing experience in Phase 3.
            </p>
          </header>

          <section className="flex flex-col gap-3">
            <Button variant="primary" arrow>
              I&apos;M IN
            </Button>
            <Button variant="secondary">ADD TO CALENDAR</Button>
            <Button variant="primary" loading>
              SUBMITTING
            </Button>
            <Button variant="primary" disabled arrow>
              RECESS IS FULL
            </Button>
            <Button variant="ghost">Back</Button>
          </section>

          <section className="flex flex-col gap-5">
            <Field
              id="name"
              label="What&rsquo;s your name?"
              defaultValue="Alfred Enyinna"
            />
            <Field
              id="alias"
              label="What do we call you?"
              hint="Your RECESS name. This is what everyone else sees."
              defaultValue="wh0isalfred"
            />
            <Field
              id="alias-taken"
              label="What do we call you?"
              defaultValue="wh0isalfred"
              error="Someone already took that one for this RECESS."
            />
          </section>

          <section className="flex flex-wrap gap-2">
            {[
              "paper",
              "paper-deep",
              "ink",
              "aubergine",
              "aubergine-lift",
              "pink",
              "pink-deep",
              "amber",
            ].map((token) => (
              <div key={token} className="flex flex-col items-center gap-1">
                <span
                  className="block h-12 w-12 rounded-rc-sm border border-ink/15"
                  style={{ backgroundColor: `var(--${token})` }}
                />
                <span className="text-rc-xs text-fg-soft">{token}</span>
              </div>
            ))}
          </section>
        </div>
      </Surface>

      <Surface as="section" ground="night" grain="low" className="px-6 py-10">
        <div className="relative z-10 mx-auto flex max-w-md flex-col gap-8">
          <header className="flex flex-col gap-2">
            <p className="text-rc-xs tracking-[0.14em] text-fg-soft">
              SAME COMPONENTS &middot; NIGHT GROUND
            </p>
            <h1 className="font-display text-rc-xl text-pink">CHECK IN</h1>
            <p className="max-w-[32ch] text-rc-base text-fg-soft">
              Nothing below is restyled. Surface changed the ground and every
              child followed.
            </p>
          </header>

          <section className="flex flex-col gap-3">
            <Button variant="primary" arrow>
              CHECK IN NOW
            </Button>
            <Button variant="secondary">SEE FULL RESULTS</Button>
          </section>

          <Field id="alias-night" label="Among Us name" defaultValue="Alfred" />
        </div>
      </Surface>
    </>
  );
}
