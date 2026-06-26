enum BookingContextMode { receiving, delivering }

enum BookingTab { upcoming, past, requests, confirmed, pastDeliveries }

enum BookingStatusTone {
  confirmed,
  awaiting,
  cancelled,
  completed,
  request,
  highlighted,
  noShow,
}

enum BookingActionStyle { primary, secondary, outline, danger }

enum BookingDetailType {
  receivingConfirmed,
  receivingRequested,
  receivingCompleted,
  deliveringRequest,
  deliveringConfirmed,
}

class BookingActionData {
  final String label;
  final BookingActionStyle style;
  final String? toastMessage;
  final bool opensDetail;

  const BookingActionData({
    required this.label,
    required this.style,
    this.toastMessage,
    this.opensDetail = false,
  });
}

class BookingRecord {
  final String id;
  final String serviceId;
  final String slotId;
  final BookingContextMode context;
  final BookingTab tab;
  final String title;
  final String subtitle;
  final String meta;
  final String reviewSummary;
  final String providerUserId;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final int pricePaise;
  final int durationMinutes;
  final String? sectionLabel;
  final String statusLabel;
  final BookingStatusTone statusTone;
  final bool isRequestHighlighted;
  final int? countdownSeconds;
  final List<BookingActionData> actions;
  final BookingDetailType? detailType;

  const BookingRecord({
    required this.id,
    required this.serviceId,
    this.slotId = '',
    required this.context,
    required this.tab,
    required this.title,
    required this.subtitle,
    required this.meta,
    this.reviewSummary = '',
    this.providerUserId = '',
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.pricePaise = 0,
    this.durationMinutes = 0,
    required this.statusLabel,
    required this.statusTone,
    this.sectionLabel,
    this.isRequestHighlighted = false,
    this.countdownSeconds,
    this.actions = const [],
    this.detailType,
  });
}
