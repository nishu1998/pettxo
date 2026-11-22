import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/presentation/widgets/comment_error_messages.dart';

FirebaseException _firebase(String code) => FirebaseException(
  plugin: 'cloud_firestore',
  code: code,
  message: 'raw platform message',
);

void main() {
  group('friendlyCommentErrorMessage', () {
    test('permission-denied maps per action', () {
      expect(
        friendlyCommentErrorMessage(
          _firebase('permission-denied'),
          CommentAction.post,
        ),
        "You can't comment on this post right now.",
      );
      expect(
        friendlyCommentErrorMessage(
          _firebase('permission-denied'),
          CommentAction.delete,
        ),
        "You can't delete this comment right now.",
      );
      expect(
        friendlyCommentErrorMessage(
          _firebase('permission-denied'),
          CommentAction.report,
        ),
        "You can't report this comment right now.",
      );
    });

    test('connection failures map to the connection message', () {
      for (final error in <Object>[
        _firebase('unavailable'),
        _firebase('deadline-exceeded'),
        _firebase('network-request-failed'),
        const SocketException('offline'),
        TimeoutException('slow'),
      ]) {
        expect(
          friendlyCommentErrorMessage(error, CommentAction.post),
          "We couldn't post your comment. Check your connection and try again.",
        );
      }
      expect(
        friendlyCommentErrorMessage(
          _firebase('unavailable'),
          CommentAction.delete,
        ),
        "We couldn't delete your comment. Check your connection and try again.",
      );
      expect(
        friendlyCommentErrorMessage(
          _firebase('unavailable'),
          CommentAction.report,
        ),
        "We couldn't report this comment. Check your connection and try again.",
      );
    });

    test('other Firebase errors map to a generic sentence', () {
      expect(
        friendlyCommentErrorMessage(_firebase('internal'), CommentAction.post),
        "We couldn't post your comment right now. Please try again.",
      );
    });

    test('keeps friendly repository messages', () {
      expect(
        friendlyCommentErrorMessage(
          Exception('This post is no longer available for comments.'),
          CommentAction.post,
        ),
        'This post is no longer available for comments.',
      );
      expect(
        friendlyCommentErrorMessage(
          Exception('You already reported this comment.'),
          CommentAction.report,
        ),
        'You already reported this comment.',
      );
    });

    test('never exposes raw platform text', () {
      for (final error in <Object>[
        _firebase('permission-denied'),
        Exception(
          '[cloud_firestore/permission-denied] The caller does not have '
          'permission to execute the specified operation.',
        ),
        StateError('boom'),
        'plain string',
      ]) {
        for (final action in CommentAction.values) {
          final message = friendlyCommentErrorMessage(error, action);
          expect(message, isNot(contains('cloud_firestore/')));
          expect(message, isNot(contains('permission-denied')));
          expect(message, isNot(contains('raw platform message')));
          expect(message, isNot(contains('boom')));
        }
      }
    });
  });
}
