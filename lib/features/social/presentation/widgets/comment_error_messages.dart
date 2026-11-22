import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

enum CommentAction { post, delete, report }

const Set<String> _connectionErrorCodes = <String>{
  'unavailable',
  'deadline-exceeded',
  'network-request-failed',
};

/// User-facing message for a failed comment post, delete or report.
///
/// Never exposes a raw FirebaseException (for example
/// "[cloud_firestore/permission-denied] ..."). Friendly messages the
/// repository throws as `Exception('...')` (such as "This post is no longer
/// available for comments.") are kept as they are.
String friendlyCommentErrorMessage(Object error, CommentAction action) {
  if (error is FirebaseException) {
    final code = error.code.trim().toLowerCase();
    if (code == 'permission-denied') return _permissionDenied(action);
    if (_connectionErrorCodes.contains(code)) return _connection(action);
    return _generic(action);
  }
  if (error is SocketException || error is TimeoutException) {
    return _connection(action);
  }

  final text = error.toString();
  const prefix = 'Exception: ';
  if (error is Exception && text.startsWith(prefix)) {
    final message = text.substring(prefix.length).trim();
    if (message.isNotEmpty && !_looksLikeRawPlatformError(message)) {
      return message;
    }
  }
  return _generic(action);
}

bool _looksLikeRawPlatformError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('cloud_firestore/') ||
      lower.contains('firebase_') ||
      lower.contains('permission-denied') ||
      lower.contains('platformexception') ||
      lower.startsWith('[');
}

String _permissionDenied(CommentAction action) {
  switch (action) {
    case CommentAction.post:
      return "You can't comment on this post right now.";
    case CommentAction.delete:
      return "You can't delete this comment right now.";
    case CommentAction.report:
      return "You can't report this comment right now.";
  }
}

String _connection(CommentAction action) {
  switch (action) {
    case CommentAction.post:
      return "We couldn't post your comment. Check your connection and try again.";
    case CommentAction.delete:
      return "We couldn't delete your comment. Check your connection and try again.";
    case CommentAction.report:
      return "We couldn't report this comment. Check your connection and try again.";
  }
}

String _generic(CommentAction action) {
  switch (action) {
    case CommentAction.post:
      return "We couldn't post your comment right now. Please try again.";
    case CommentAction.delete:
      return "We couldn't delete your comment right now. Please try again.";
    case CommentAction.report:
      return "We couldn't report this comment right now. Please try again.";
  }
}
