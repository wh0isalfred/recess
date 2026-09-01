import { Surface } from "@/components/ui/Surface";

/**
 * Placeholder. The public landing experience is Phase 3; this exists only so
 * the route resolves. The Phase 0 foundation-check page it replaces is now
 * covered properly by /design-system.
 */
export default function HomePage() {
  return (
    <Surface as="main" ground="paper" grain="high" className="grid min-h-dvh place-items-center px-6">
      <div className="relative z-10 text-center">
        <h1 className="font-display text-rc-2xl">RECESS</h1>
        <p className="mt-3 text-rc-base text-fg-soft">Coming soon.</p>
      </div>
    </Surface>
  );
}
