/// A Pettxo Offer calendar date in the fixed Asia/Kolkata business timezone.
///
/// This deliberately avoids device-local timezone conversion. Canonical Offer
/// ends are stored as midnight IST immediately after the last valid day.
class OfferBusinessDate {
  const OfferBusinessDate(this.year, this.month, this.day);

  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  final int year;
  final int month;
  final int day;

  factory OfferBusinessDate.fromInstant(DateTime instant) {
    final istValue = instant.toUtc().add(istOffset);
    return OfferBusinessDate(istValue.year, istValue.month, istValue.day);
  }

  /// Derives the inclusive business date represented by an Offer end instant.
  ///
  /// Exact midnight IST is the canonical exclusive boundary and therefore
  /// belongs to the preceding valid day. Arbitrary legacy times retain their
  /// own IST calendar date and are not shifted by an additional day.
  factory OfferBusinessDate.validThrough(DateTime endAt) {
    final istBoundary = endAt.toUtc().add(istOffset);
    final isCanonicalExclusiveBoundary =
        istBoundary.hour == 0 &&
        istBoundary.minute == 0 &&
        istBoundary.second == 0 &&
        istBoundary.millisecond == 0 &&
        istBoundary.microsecond == 0;
    return OfferBusinessDate.fromInstant(
      isCanonicalExclusiveBoundary
          ? endAt.subtract(const Duration(microseconds: 1))
          : endAt,
    );
  }
}
