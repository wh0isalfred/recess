import { PlayMark } from "@/components/brand/PlayMark";

/**
 * checked_in_at IS NOT NULL + no active room_membership — exactly what
 * migration 0017 already models as CHECKED_IN_WAITING, with nothing invented
 * here: no room number, no room WhatsApp link, no client-side assignment.
 * Admin's ASSIGN WAITING PLAYERS (or the player's own next refresh once a
 * room opens up) is what moves this to ROOM_ASSIGNED — this screen does not
 * poll or guess at that, it just states the true, current fact.
 */
export function WaitingForRoomScreen() {
  return (
    <div className="rc-room-stage rc-room-stage--waiting">
      <PlayMark className="rc-room-waiting-mark" />
      <h1 className="rc-room-waiting-heading">YOU&rsquo;RE CHECKED IN.</h1>
      <p className="rc-room-waiting-sub">HANG TIGHT.</p>
      <p className="rc-room-waiting-copy">We&rsquo;re getting a room ready for you.</p>
    </div>
  );
}
