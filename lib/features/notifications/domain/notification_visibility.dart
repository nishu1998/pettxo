class NotificationVisibility {
  const NotificationVisibility._();

  static const List<String> _orderedChannels = <String>[
    'in_app',
    'push',
    'whatsapp',
  ];

  static List<String>? parseChannels(dynamic value) {
    if (value == null) return null;
    if (value is! List) return <String>[];
    return _orderedChannels
        .where((channel) => value.contains(channel))
        .toList(growable: false);
  }

  static bool isVisibleInApp(Map<String, dynamic> data) {
    final visibleInApp = data['visibleInApp'];
    if (visibleInApp is bool) return visibleInApp;
    final channels = parseChannels(data['channels']);
    if (channels == null) return true;
    return channels.contains('in_app');
  }
}
