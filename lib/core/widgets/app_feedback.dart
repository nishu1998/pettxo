import 'package:flutter/material.dart';

import 'app_snackbar.dart';

enum AppFeedbackTone { success, error, warning, info }

class AppFeedback {
  static void show(
    BuildContext context, {
    required String message,
    AppFeedbackTone tone = AppFeedbackTone.info,
  }) {
    switch (tone) {
      case AppFeedbackTone.success:
        AppSnackbar.showSuccess(context, message);
        break;
      case AppFeedbackTone.error:
        AppSnackbar.showError(context, message);
        break;
      case AppFeedbackTone.warning:
        AppSnackbar.showWarning(context, message);
        break;
      case AppFeedbackTone.info:
        AppSnackbar.showInfo(context, message);
        break;
    }
  }
}
