"use client";

import { useState, useSyncExternalStore } from "react";
import { Button } from "@/components/ui/Button";
import { WhatsAppIcon, ArrowRightIcon } from "@/components/brand/v2/icons";
import { isValidWhatsAppGroupUrl } from "@/features/registration/calendar";
import { hasOpenedWhatsApp, markWhatsAppOpened } from "@/features/pass/whatsappOpened";

const NO_SUBSCRIPTION = () => () => {};

/**
 * Two presentations of the same action, never two different claims: we only
 * ever know the player *opened* the link, never that they joined the group
 * (an external app). "Opened" persists per real event+registration id (see
 * whatsappOpened.ts) so a refresh doesn't re-show the hot-pink first-open
 * state, and a different future event's Pass starts fresh.
 *
 * useSyncExternalStore, not useState+useEffect: the server always renders
 * as if nothing is opened yet (no localStorage there), and the real
 * client-side value — possibly different — arrives via this hook's
 * dedicated path for exactly that, without a hydration-mismatch warning or
 * a setState-in-effect cascade. Same mechanism this codebase already uses
 * for the pass-fresh flag.
 */
export function WhatsAppCta({
  whatsappGroupUrl,
  eventId,
  registrationId,
}: {
  whatsappGroupUrl: string | null;
  eventId: string;
  registrationId: string;
}) {
  const initiallyOpened = useSyncExternalStore(
    NO_SUBSCRIPTION,
    () => hasOpenedWhatsApp(eventId, registrationId),
    () => false,
  );
  const [justOpened, setJustOpened] = useState(false);
  const opened = initiallyOpened || justOpened;

  const hasGroup = isValidWhatsAppGroupUrl(whatsappGroupUrl);

  if (!hasGroup) {
    return (
      <div className="rc-pass2-cta">
        <p className="rc-pass2-cta-pending" aria-live="polite">
          WhatsApp group link coming soon
        </p>
      </div>
    );
  }

  return (
    <div className="rc-pass2-cta">
      <Button
        href={whatsappGroupUrl!}
        external
        variant={opened ? "poster-quiet" : "poster"}
        size="lg"
        onClick={() => {
          markWhatsAppOpened(eventId, registrationId);
          setJustOpened(true);
        }}
      >
        <span className="rc-pass2-cta-label">
          <WhatsAppIcon className="rc-pass2-cta-icon" />
          {opened ? "OPEN WHATSAPP GROUP" : "JOIN THE WHATSAPP GROUP"}
          <ArrowRightIcon className="rc-pass2-cta-arrow" />
        </span>
      </Button>
      <p className="rc-pass2-cta-helper">
        {opened
          ? "You\u2019re set. Come back here when check-in opens."
          : "Join the group for updates, then come back here when check-in opens."}
      </p>
    </div>
  );
}
