import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

enum ReportSubmissionFailureKind {
  unauthenticated,
  permissionDenied,
  invalidArgument,
  notFound,
  alreadyReported,
  unavailable,
  timeout,
  unexpected,
}

class ReportSubmissionException implements Exception {
  const ReportSubmissionException(this.kind);

  final ReportSubmissionFailureKind kind;

  String get userMessage {
    switch (kind) {
      case ReportSubmissionFailureKind.unauthenticated:
        return 'Please sign in to submit a report.';
      case ReportSubmissionFailureKind.permissionDenied:
        return 'You do not have permission to report this content.';
      case ReportSubmissionFailureKind.invalidArgument:
        return 'Please check the report details and try again.';
      case ReportSubmissionFailureKind.notFound:
        return 'This content is no longer available to report.';
      case ReportSubmissionFailureKind.alreadyReported:
        return "You've already reported this.";
      case ReportSubmissionFailureKind.unavailable:
        return 'Check your connection and try again.';
      case ReportSubmissionFailureKind.timeout:
        return 'The report request timed out. Please try again.';
      case ReportSubmissionFailureKind.unexpected:
        return 'We could not submit your report right now.';
    }
  }
}

class ReportSubmissionResult {
  const ReportSubmissionResult({
    required this.reportId,
    required this.status,
    required this.duplicate,
  });

  final String reportId;
  final String status;
  final bool duplicate;
}

class ReportRepository {
  ReportRepository({
    FirebaseFunctions? functions,
    Duration timeout = const Duration(seconds: 15),
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       _timeout = timeout;

  final FirebaseFunctions _functions;
  final Duration _timeout;

  static String reasonCodeForLabel(String label) {
    switch (label.trim().toLowerCase()) {
      case 'spam':
        return 'spam';
      case 'fake information':
        return 'fake_information';
      case 'harassment':
      case 'abusive or harmful':
        return 'abusive_or_harmful';
      case 'inappropriate content':
        return 'inappropriate_content';
      case 'safety concern':
        return 'safety_concern';
      case 'other':
        return 'other';
      default:
        throw const ReportSubmissionException(
          ReportSubmissionFailureKind.invalidArgument,
        );
    }
  }

  Future<ReportSubmissionResult> createReport({
    required String type,
    required String targetId,
    required String reason,
    String? contextId,
    String? description,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    final normalizedTargetId = targetId.trim();
    final normalizedContextId = contextId?.trim() ?? '';
    final normalizedDescription = description?.trim() ?? '';

    if ((normalizedType != 'service' && normalizedType != 'review') ||
        normalizedTargetId.isEmpty ||
        (normalizedType == 'review' && normalizedContextId.isEmpty) ||
        (normalizedType == 'service' && normalizedContextId.isNotEmpty)) {
      throw const ReportSubmissionException(
        ReportSubmissionFailureKind.invalidArgument,
      );
    }

    final payload = <String, dynamic>{
      'type': normalizedType,
      'targetId': normalizedTargetId,
      if (normalizedType == 'review') 'contextId': normalizedContextId,
      'reason': reasonCodeForLabel(reason),
      if (normalizedDescription.isNotEmpty)
        'description': normalizedDescription,
    };

    try {
      final callable = _functions.httpsCallable('submitReport');
      final response = await callable
          .call<Map<String, dynamic>>(payload)
          .timeout(_timeout);
      final data = response.data;
      final reportId = data['reportId'];
      final status = data['status'];
      final duplicate = data['duplicate'];
      if (reportId is! String ||
          reportId.trim().isEmpty ||
          status != 'pending' ||
          duplicate is! bool) {
        throw const ReportSubmissionException(
          ReportSubmissionFailureKind.unexpected,
        );
      }
      return ReportSubmissionResult(
        reportId: reportId,
        status: status as String,
        duplicate: duplicate,
      );
    } on ReportSubmissionException {
      rethrow;
    } on TimeoutException {
      throw const ReportSubmissionException(
        ReportSubmissionFailureKind.timeout,
      );
    } on FirebaseFunctionsException catch (error) {
      throw ReportSubmissionException(_failureKindForCode(error.code));
    } catch (_) {
      throw const ReportSubmissionException(
        ReportSubmissionFailureKind.unexpected,
      );
    }
  }

  ReportSubmissionFailureKind _failureKindForCode(String code) {
    switch (code.trim().toLowerCase()) {
      case 'unauthenticated':
        return ReportSubmissionFailureKind.unauthenticated;
      case 'permission-denied':
        return ReportSubmissionFailureKind.permissionDenied;
      case 'invalid-argument':
        return ReportSubmissionFailureKind.invalidArgument;
      case 'not-found':
        return ReportSubmissionFailureKind.notFound;
      case 'already-exists':
        return ReportSubmissionFailureKind.alreadyReported;
      case 'unavailable':
      case 'network-request-failed':
        return ReportSubmissionFailureKind.unavailable;
      case 'deadline-exceeded':
        return ReportSubmissionFailureKind.timeout;
      default:
        return ReportSubmissionFailureKind.unexpected;
    }
  }
}
