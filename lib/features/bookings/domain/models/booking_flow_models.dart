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
  final BookingContextMode context;
  final BookingTab tab;
  final String title;
  final String subtitle;
  final String meta;
  final String? sectionLabel;
  final String statusLabel;
  final BookingStatusTone statusTone;
  final bool isRequestHighlighted;
  final int? countdownSeconds;
  final List<BookingActionData> actions;
  final BookingDetailType? detailType;

  const BookingRecord({
    required this.id,
    required this.context,
    required this.tab,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.statusLabel,
    required this.statusTone,
    this.sectionLabel,
    this.isRequestHighlighted = false,
    this.countdownSeconds,
    this.actions = const [],
    this.detailType,
  });
}
