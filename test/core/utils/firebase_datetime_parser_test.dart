import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/utils/firebase_datetime_parser.dart';

void main() {
  group('parseFirebaseDateTime', () {
    test('parses native Timestamp', () {
      final timestamp = Timestamp.fromDate(DateTime.utc(2026, 8, 1, 10, 15));

      final parsed = parseFirebaseDateTime(timestamp);

      expect(parsed, isNotNull);
      expect(
        parsed!.millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 1, 10, 15).millisecondsSinceEpoch,
      );
    });

    test('parses DateTime', () {
      final date = DateTime.utc(2026, 8, 2, 8, 30);

      final parsed = parseFirebaseDateTime(date);

      expect(parsed, date);
    });

    test('parses epoch milliseconds', () {
      final parsed = parseFirebaseDateTime(1754217000000);

      expect(parsed, isNotNull);
      expect(parsed!.millisecondsSinceEpoch, 1754217000000);
    });

    test('parses epoch seconds', () {
      final parsed = parseFirebaseDateTime(1754217000);

      expect(parsed, isNotNull);
      expect(parsed!.millisecondsSinceEpoch, 1754217000000);
    });

    test('parses ISO string', () {
      final parsed = parseFirebaseDateTime('2026-08-03T12:30:00.000Z');

      expect(parsed, DateTime.parse('2026-08-03T12:30:00.000Z'));
    });

    test('parses map with underscored timestamp keys', () {
      final parsed = parseFirebaseDateTime({
        '_seconds': 1754217000,
        '_nanoseconds': 250000000,
      });

      expect(parsed, isNotNull);
      expect(parsed!.millisecondsSinceEpoch, 1754217000250);
    });

    test('parses map with plain timestamp keys', () {
      final parsed = parseFirebaseDateTime({
        'seconds': 1754217000,
        'nanoseconds': 500000000,
      });

      expect(parsed, isNotNull);
      expect(parsed!.millisecondsSinceEpoch, 1754217000500);
    });

    test('parses _Map<Object?, Object?> shape', () {
      final value = <Object?, Object?>{
        '_seconds': 1754217000,
        '_nanoseconds': 0,
      };

      final parsed = parseFirebaseDateTime(value);

      expect(parsed, isNotNull);
      expect(parsed!.millisecondsSinceEpoch, 1754217000000);
    });

    test('returns null for null', () {
      expect(parseFirebaseDateTime(null), isNull);
    });

    test('returns null for malformed map', () {
      expect(parseFirebaseDateTime({'seconds': 'bad'}), isNull);
    });

    test('returns null for invalid string', () {
      expect(parseFirebaseDateTime('not-a-date'), isNull);
    });
  });

  group('parseFirebaseTimestamp', () {
    test('returns Timestamp from callable map', () {
      final parsed = parseFirebaseTimestamp({
        '_seconds': 1754217000,
        '_nanoseconds': 1000000,
      });

      expect(parsed, isNotNull);
      expect(parsed!.millisecondsSinceEpoch, 1754217000001);
    });
  });
}
