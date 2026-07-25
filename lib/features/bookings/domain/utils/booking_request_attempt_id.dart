import 'dart:math';

class BookingRequestAttemptIdController {
  static final Random _random = Random.secure();

  String? _activeAttemptId;
  String? _activePayloadKey;

  String idForPayload(String payloadKey) {
    final normalizedKey = payloadKey.trim();
    if (_activeAttemptId != null && _activePayloadKey == normalizedKey) {
      return _activeAttemptId!;
    }
    _activePayloadKey = normalizedKey;
    _activeAttemptId = generate();
    return _activeAttemptId!;
  }

  String get activeAttemptId => _activeAttemptId ?? generate();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20, 32),
    ].join('-');
  }
}
