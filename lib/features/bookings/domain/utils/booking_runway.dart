const int canonicalBookingAcceptWindowMinutes = 60;
const int canonicalBookingPayWindowMinutes = 60;
const int canonicalBookingSafetyBufferMinutes = 30;
const int canonicalBookingRunwayMinutes = 150;

DateTime computeCanonicalBookingRunwayEndsAt(DateTime authoritativeNow) {
  return authoritativeNow.add(
    const Duration(minutes: canonicalBookingRunwayMinutes),
  );
}

bool isCanonicalBookingAnchorBookable({
  required DateTime anchorAt,
  required DateTime authoritativeNow,
}) {
  return !anchorAt.isBefore(
    computeCanonicalBookingRunwayEndsAt(authoritativeNow),
  );
}
