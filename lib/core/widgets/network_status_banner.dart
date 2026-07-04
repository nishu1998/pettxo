import 'package:flutter/material.dart';

import '../services/network_status_service.dart';

class NetworkStatusBannerHost extends StatelessWidget {
  final Widget child;

  const NetworkStatusBannerHost({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 32;

    return Stack(
      children: [
        child,
        ValueListenableBuilder<bool>(
          valueListenable: NetworkStatusService.instance.isOnlineListenable,
          builder: (context, isOnline, _) {
            return IgnorePointer(
              ignoring: isOnline,
              child: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    offset: isOnline ? const Offset(0, -1.2) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: isOnline ? 0 : 1,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF252525).withValues(
                              alpha: 0.96,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border(
                              top: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 20,
                                spreadRadius: 1,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: const TextScaler.linear(1.0),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Color(0x22FFFFFF),
                                  child: Icon(
                                    Icons.cloud_off_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "You're Offline",
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Showing saved content',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    height: 1.1,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}