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

const List<BookingRecord> bookingRecords = [
  BookingRecord(
    id: 'receiving-confirmed',
    context: BookingContextMode.receiving,
    tab: BookingTab.upcoming,
    sectionLabel: '2 upcoming',
    title: 'Daily Dog Walk',
    subtitle: '🐕 Dog · Ravi Sharma',
    statusLabel: 'Confirmed',
    statusTone: BookingStatusTone.confirmed,
    meta: 'Tomorrow, 8:00 AM · 60 min',
    actions: [
      BookingActionData(
        label: 'View booking',
        style: BookingActionStyle.primary,
        opensDetail: true,
      ),
    ],
    detailType: BookingDetailType.receivingConfirmed,
  ),
  BookingRecord(
    id: 'receiving-requested',
    context: BookingContextMode.receiving,
    tab: BookingTab.upcoming,
    title: 'Cat Grooming Session',
    subtitle: '🐱 Cat · Priya\'s Pet Salon',
    statusLabel: 'Awaiting confirm',
    statusTone: BookingStatusTone.awaiting,
    meta: 'Sat 19 Apr, 11:00 AM · 90 min',
    countdownSeconds: 1123,
    detailType: BookingDetailType.receivingRequested,
  ),
  BookingRecord(
    id: 'receiving-completed',
    context: BookingContextMode.receiving,
    tab: BookingTab.past,
    sectionLabel: 'Past bookings',
    title: 'Dog Grooming Session',
    subtitle: '🐕 Dog · Furr & Fresh Salon',
    statusLabel: 'Completed',
    statusTone: BookingStatusTone.completed,
    meta: '5 Apr 2025',
    detailType: BookingDetailType.receivingCompleted,
  ),
  BookingRecord(
    id: 'receiving-cancelled',
    context: BookingContextMode.receiving,
    tab: BookingTab.past,
    title: 'Dog Boarding',
    subtitle: '🐕 Dog · Happy Paws Stay',
    statusLabel: 'Cancelled',
    statusTone: BookingStatusTone.cancelled,
    meta: '28 Mar 2025',
  ),
  BookingRecord(
    id: 'receiving-no-show',
    context: BookingContextMode.receiving,
    tab: BookingTab.past,
    title: 'Cat Boarding',
    subtitle: '🐱 Cat · Kitty\'s Retreat',
    statusLabel: 'No-show',
    statusTone: BookingStatusTone.noShow,
    meta: '15 Mar 2025',
    actions: [
      BookingActionData(
        label: 'Raise an issue',
        style: BookingActionStyle.outline,
        toastMessage: 'Issue reporting flow opened.',
      ),
    ],
  ),
  BookingRecord(
    id: 'delivering-request',
    context: BookingContextMode.delivering,
    tab: BookingTab.requests,
    sectionLabel: '2 pending requests',
    title: 'Anjali Mehta',
    subtitle: '🐕 Dog · Daily Dog Walk',
    statusLabel: 'Request',
    statusTone: BookingStatusTone.highlighted,
    meta: 'Today, 5:00 PM · 60 min',
    countdownSeconds: 1330,
    isRequestHighlighted: true,
    actions: [
      BookingActionData(
        label: 'Accept',
        style: BookingActionStyle.primary,
        toastMessage: 'Booking accepted!',
      ),
      BookingActionData(
        label: 'Reject',
        style: BookingActionStyle.danger,
        toastMessage: 'Booking rejected.',
      ),
    ],
    detailType: BookingDetailType.deliveringRequest,
  ),
  BookingRecord(
    id: 'delivering-request-2',
    context: BookingContextMode.delivering,
    tab: BookingTab.requests,
    title: 'Rohan Gupta',
    subtitle: '🐱 Cat · Cat Grooming Session',
    statusLabel: 'Request',
    statusTone: BookingStatusTone.highlighted,
    meta: 'Sat 19 Apr, 2:00 PM · 90 min',
    countdownSeconds: 6330,
    isRequestHighlighted: true,
    actions: [
      BookingActionData(
        label: 'Accept',
        style: BookingActionStyle.primary,
        toastMessage: 'Booking accepted!',
      ),
      BookingActionData(
        label: 'Reject',
        style: BookingActionStyle.danger,
        toastMessage: 'Booking rejected.',
      ),
    ],
  ),
  BookingRecord(
    id: 'delivering-confirmed',
    context: BookingContextMode.delivering,
    tab: BookingTab.confirmed,
    sectionLabel: '1 confirmed',
    title: 'Meera Joshi',
    subtitle: '🐕 Dog · Dog Bath & Brush',
    statusLabel: 'In ~2 hrs',
    statusTone: BookingStatusTone.request,
    meta: 'Today, 3:00 PM · 60 min',
    actions: [
      BookingActionData(
        label: 'Start service',
        style: BookingActionStyle.primary,
        opensDetail: true,
      ),
      BookingActionData(
        label: 'Message',
        style: BookingActionStyle.secondary,
        toastMessage: 'Messaging flow opened.',
      ),
    ],
    detailType: BookingDetailType.deliveringConfirmed,
  ),
  BookingRecord(
    id: 'delivering-past-completed',
    context: BookingContextMode.delivering,
    tab: BookingTab.pastDeliveries,
    sectionLabel: 'Past deliveries',
    title: 'Sanket Patel',
    subtitle: '🐕 Dog · Daily Dog Walk',
    statusLabel: 'Completed',
    statusTone: BookingStatusTone.completed,
    meta: '9 Apr 2025 · Earned: ₹298',
  ),
  BookingRecord(
    id: 'delivering-past-cancelled',
    context: BookingContextMode.delivering,
    tab: BookingTab.pastDeliveries,
    title: 'Pooja Nair',
    subtitle: '🐕 Dog · Dog Boarding',
    statusLabel: 'Cancelled by provider',
    statusTone: BookingStatusTone.cancelled,
    meta: '2 Apr 2025',
  ),
];
