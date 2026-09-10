import { RecessWordmarkV2 } from "@/components/brand/v2/RecessWordmark";

/**
 * The restrained, full-page branded loader — replaces a blank cream div
 * for initial app load / whole-page navigations that have nowhere
 * persistent to show a skeleton inside of (e.g. the root "/" route, or an
 * identity-guard redirect boundary). Not used for registered-player
 * content transitions — see PlayerContentSkeleton for that, where the
 * shell/nav themselves stay mounted and only the content slot needs a
 * loading treatment.
 *
 * The wordmark itself is static; only its opacity breathes, gently, and
 * only when the visitor hasn't asked for reduced motion — see
 * loaders.css. No spinner, no logo rotation, no skeleton bars: at this
 * boundary there's no known content shape yet to hint at.
 */
export function RecessLoader() {
  return (
    <div className="rc-loader-page" role="status" aria-label="Loading RECESS">
      <RecessWordmarkV2 className="rc-loader-mark" />
    </div>
  );
}
