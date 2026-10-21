import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/pettxo_full_screen_loader.dart';
import 'app_update_service.dart';
import 'mandatory_update_screen.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child, this.controller});

  final Widget child;
  final AppUpdateController? controller;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  late final AppUpdateController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppUpdateController.production();
    _controller.addListener(_handleChanged);
    unawaited(_controller.initialize());
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _controller.status == AppUpdateGateStatus.blocked;
    final checking = _controller.status == AppUpdateGateStatus.checking;
    return PopScope(
      canPop: !blocked && !checking,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: blocked || checking,
            child: ExcludeSemantics(
              excluding: blocked || checking,
              child: widget.child,
            ),
          ),
          if (checking)
            const PettxoFullScreenLoader(
              message: 'Checking your Pettxo experience…',
              mode: PettxoFullScreenLoaderMode.opaque,
            ),
          if (blocked)
            Positioned.fill(
              child: MandatoryUpdateScreen(
                message: _controller.policy.message,
                isUpdating: _controller.actionInProgress,
                lastResult: _controller.lastActionResult,
                onUpdate: _controller.launchUpdate,
                onRetry: _controller.refresh,
              ),
            ),
        ],
      ),
    );
  }
}
