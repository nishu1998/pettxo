import 'dart:async';

import 'package:flutter/material.dart';

const double kHomeFeedRefreshTriggerPullDistance = 72;

class HomeFeedRefreshSurface extends StatefulWidget {
  const HomeFeedRefreshSurface({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
    this.triggerPullDistance = kHomeFeedRefreshTriggerPullDistance,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double edgeOffset;
  final double triggerPullDistance;

  @override
  State<HomeFeedRefreshSurface> createState() => HomeFeedRefreshSurfaceState();
}

class HomeFeedRefreshSurfaceState extends State<HomeFeedRefreshSurface> {
  final GlobalKey<RefreshIndicatorState> _indicatorKey =
      GlobalKey<RefreshIndicatorState>();

  bool _refreshInFlight = false;
  bool _refreshCallbackInFlight = false;
  bool _triggeredForCurrentDrag = false;
  double _dragPullDistance = 0;

  Future<void> show() async {
    if (_refreshInFlight) return;
    final indicator = _indicatorKey.currentState;
    if (indicator == null) return;

    _refreshInFlight = true;
    try {
      await indicator.show();
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _handleRefresh() async {
    if (_refreshCallbackInFlight) return;
    _refreshCallbackInFlight = true;
    try {
      await widget.onRefresh();
    } finally {
      _refreshCallbackInFlight = false;
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _triggeredForCurrentDrag = false;
      _dragPullDistance = 0;
    } else if (notification is ScrollEndNotification) {
      _triggeredForCurrentDrag = false;
      _dragPullDistance = 0;
    } else if (notification is ScrollUpdateNotification &&
        !_triggeredForCurrentDrag &&
        !_refreshInFlight) {
      final dragDelta = notification.dragDetails?.primaryDelta ?? 0;
      final isAtTop =
          notification.metrics.extentBefore == 0 ||
          notification.metrics.pixels <= notification.metrics.minScrollExtent;
      if (isAtTop && dragDelta > 0) {
        _dragPullDistance += dragDelta;
      } else if (dragDelta < 0) {
        _dragPullDistance = 0;
      }
      if (_dragPullDistance >= widget.triggerPullDistance) {
        _triggeredForCurrentDrag = true;
        unawaited(show());
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: RefreshIndicator(
        key: _indicatorKey,
        edgeOffset: widget.edgeOffset,
        onRefresh: _handleRefresh,
        child: widget.child,
      ),
    );
  }
}

class HomeTabReselectCoordinator {
  bool _isHandling = false;

  bool get isHandling => _isHandling;

  Future<void> scrollToTopAndRefresh({
    required ScrollController scrollController,
    required Future<void> Function() refresh,
  }) async {
    if (_isHandling) return;
    _isHandling = true;
    try {
      if (scrollController.hasClients) {
        final position = scrollController.position;
        if (position.pixels > position.minScrollExtent) {
          await scrollController.animateTo(
            position.minScrollExtent,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }
      }
      await refresh();
    } finally {
      _isHandling = false;
    }
  }
}
