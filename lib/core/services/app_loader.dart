import 'package:flutter/material.dart';

import '../widgets/paw_loading_overlay.dart';

class AppLoader {
  AppLoader._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final ValueNotifier<String?> _messageNotifier = ValueNotifier<String?>(
    null,
  );

  static OverlayEntry? _overlayEntry;

  static bool get isShowing => _overlayEntry != null;

  static void show([String? message]) {
    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    _messageNotifier.value = message;

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return PawLoadingOverlay(messageListenable: _messageNotifier);
      },
    );

    overlayState.insert(_overlayEntry!);
  }

  static void showWithMessage(String message) => show(message);

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _messageNotifier.value = null;
  }
}
