import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  group('SocialPostModel.fromMap', () {
    test('preserves Firestore Timestamp parsing', () {
      final createdAt = Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9));
      final updatedAt = Timestamp.fromDate(DateTime.utc(2026, 8, 1, 10));

      final post = SocialPostModel.fromMap({
        'id': 'post-firestore',
        'authorId': 'author-1',
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdAtEpoch': createdAt.millisecondsSinceEpoch,
      });

      expect(post.createdAt, createdAt);
      expect(post.updatedAt, updatedAt);
      expect(post.createdAtEpoch, createdAt.millisecondsSinceEpoch);
    });

    test('parses callable timestamp map fields safely', () {
      final post = SocialPostModel.fromMap({
        'id': 'post-callable',
        'authorId': 'author-2',
        'feedLocationUpdatedAt': {'_seconds': 1754217000, '_nanoseconds': 0},
        'moderatedAt': {'seconds': 1754217600, 'nanoseconds': 0},
        'lastReportedAt': '2026-08-03T12:35:00.000Z',
        'createdAt': {'_seconds': 1754216400, '_nanoseconds': 500000000},
        'updatedAt': 1754218200000,
      });

      expect(post.feedLocationUpdatedAt, isNotNull);
      expect(post.moderatedAt, isNotNull);
      expect(post.lastReportedAt, isNotNull);
      expect(post.createdAt, isNotNull);
      expect(post.updatedAt, isNotNull);
      expect(post.createdAtEpoch, 1754216400500);
    });

    test('falls back to zero createdAtEpoch for malformed createdAt', () {
      final post = SocialPostModel.fromMap({
        'id': 'post-invalid',
        'authorId': 'author-3',
        'createdAt': {'seconds': 'bad'},
      });

      expect(post.createdAt, isNull);
      expect(post.createdAtEpoch, 0);
    });
  });
}
