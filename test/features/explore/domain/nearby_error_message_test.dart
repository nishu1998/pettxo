import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/domain/utils/nearby_error_message.dart';

void main() {
  group('nearbyLoadErrorMessage', () {
    test('hides raw parser type errors', () {
      final message = nearbyLoadErrorMessage(
        "type '_Map<Object?, Object?>' is not a subtype of type 'Timestamp?' in type cast",
      );

      expect(message, 'We couldn’t load nearby posts. Please try again.');
    });

    test('preserves friendly non-parser messages', () {
      final message = nearbyLoadErrorMessage(
        Exception('Please sign in again to use Nearby you.'),
      );

      expect(message, 'Please sign in again to use Nearby you.');
    });
  });
}
