import {FieldValue, type Firestore, type Transaction} from "firebase-admin/firestore";
import type {CanonicalSlotScheduleV3} from "../schema/bookingDocumentV3";
import {normalizeTimestampLike as asDate} from "../schema/timestampNormalization";

/** Server-written creation boundary. Never inferred from booking age. */
export const CONTINUOUS_LIFECYCLE_POLICY_V3 = "continuous_v1" as const;

/** Preserve processing for old schedules the prior no-show resolver accepted.
 * The new continuous validator must already have passed. Combined multi-slot
 * segments rejected by the old resolver require a release marker or Phase 2.
 */
export function legacyNoShowDeadlineCompatibleV3(schedule: CanonicalSlotScheduleV3): boolean {
  const segmentEnds = (schedule.segments ?? []).map(s => asDate(s.endAt))
    .filter((d): d is Date => d != null);
  const segmentEnd = segmentEnds.length ? Math.min(...segmentEnds.map(d => d.getTime())) : null;
  const firstSlotEnd = Math.min(...schedule.slots.map(s => asDate(s.endAt)!.getTime()));
  const additiveEnd = asDate(schedule.firstSegmentEndAt)?.getTime();
  return !(segmentEnd != null &&
    (segmentEnd !== firstSlotEnd || (additiveEnd != null && additiveEnd !== segmentEnd)));
}

export const LIFECYCLE_RELEASE_BOUNDARIES_V3 = "bookingLifecycleReleaseBoundaries";

/** Only the CREATED branch calls this, in the same transaction as the booking.
 * A sidecar survives full-document replacements by older deployed handlers.
 */
export function writeLifecycleReleaseBoundaryV3(params: {
  firestore: Firestore; transaction: Transaction; bookingId: string;
  booking: {providerId: string; parentId: string};
}): void {
  params.transaction.set(params.firestore.collection(LIFECYCLE_RELEASE_BOUNDARIES_V3).doc(params.bookingId), {
    bookingId: params.bookingId, providerId: params.booking.providerId, parentId: params.booking.parentId,
    policyVersion: CONTINUOUS_LIFECYCLE_POLICY_V3, createdAt: FieldValue.serverTimestamp(),
  });
}
