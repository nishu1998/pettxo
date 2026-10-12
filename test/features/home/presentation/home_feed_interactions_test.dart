import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/navigation/social_app_tab.dart';
import 'package:pettexo/core/widgets/social_bottom_nav.dart';
import 'package:pettexo/features/home/presentation/widgets/home_feed_refresh_surface.dart';

void main() {
  testWidgets('a short pull refreshes a short feed exactly once', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      _refreshTestApp(
        onRefresh: () async => refreshCount += 1,
        children: const <Widget>[SizedBox(height: 80, child: Text('post'))],
      ),
    );

    await tester.drag(find.text('post'), const Offset(0, 80));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(refreshCount, 1);
  });

  testWidgets('an empty feed remains pull-to-refreshable', (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      _refreshTestApp(
        onRefresh: () async => refreshCount += 1,
        children: const <Widget>[Text('No posts yet')],
      ),
    );

    await tester.drag(find.text('No posts yet'), const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(refreshCount, 1);
  });

  testWidgets('pull gestures cannot overlap an active refresh', (tester) async {
    final refreshCompleter = Completer<void>();
    var refreshCount = 0;
    await tester.pumpWidget(
      _refreshTestApp(
        onRefresh: () {
          refreshCount += 1;
          return refreshCompleter.future;
        },
        children: const <Widget>[Text('post')],
      ),
    );

    await tester.drag(find.text('post'), const Offset(0, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(refreshCount, 1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.drag(find.text('post'), const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 300));

    expect(refreshCount, 1);
    refreshCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Home reselect scrolls to top before refreshing', (tester) async {
    final controller = ScrollController(initialScrollOffset: 600);
    final coordinator = HomeTabReselectCoordinator();
    var offsetWhenRefreshed = -1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 30,
          itemExtent: 80,
          itemBuilder: (_, index) => Text('post $index'),
        ),
      ),
    );

    final operation = coordinator.scrollToTopAndRefresh(
      scrollController: controller,
      refresh: () async => offsetWhenRefreshed = controller.offset,
    );
    await tester.pumpAndSettle();
    await operation;

    expect(controller.offset, 0);
    expect(offsetWhenRefreshed, 0);
    controller.dispose();
  });

  testWidgets('Home reselect at the top still refreshes', (tester) async {
    final controller = ScrollController();
    final coordinator = HomeTabReselectCoordinator();
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: const <Widget>[Text('first post')],
        ),
      ),
    );

    await coordinator.scrollToTopAndRefresh(
      scrollController: controller,
      refresh: () async => refreshCount += 1,
    );

    expect(refreshCount, 1);
    expect(controller.offset, 0);
    controller.dispose();
  });

  testWidgets('rapid Home reselects do not overlap refreshes', (tester) async {
    final controller = ScrollController();
    final coordinator = HomeTabReselectCoordinator();
    final refreshCompleter = Completer<void>();
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: const <Widget>[Text('first post')],
        ),
      ),
    );

    final first = coordinator.scrollToTopAndRefresh(
      scrollController: controller,
      refresh: () {
        refreshCount += 1;
        return refreshCompleter.future;
      },
    );
    await tester.pump();
    await coordinator.scrollToTopAndRefresh(
      scrollController: controller,
      refresh: () async => refreshCount += 1,
    );

    expect(refreshCount, 1);
    refreshCompleter.complete();
    await first;
  });

  testWidgets('active Home tap invokes callback without navigation', (
    tester,
  ) async {
    var activeTapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Text('Home feed'),
          bottomNavigationBar: SocialBottomNav(
            activeTab: SocialAppTab.home,
            onActiveTabTap: () => activeTapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(activeTapCount, 1);
    expect(find.text('Home feed'), findsOneWidget);
  });

  testWidgets('switching to Home follows existing navigation behavior', (
    tester,
  ) async {
    var activeTapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/explore',
        routes: <String, WidgetBuilder>{
          '/': (_) => const SizedBox.shrink(),
          '/home': (_) => const Scaffold(body: Text('Existing Home route')),
          '/explore': (_) => Scaffold(
            body: const Text('Explore screen'),
            bottomNavigationBar: SocialBottomNav(
              activeTab: SocialAppTab.explore,
              onActiveTabTap: () => activeTapCount += 1,
            ),
          ),
        },
      ),
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Existing Home route'), findsOneWidget);
    expect(activeTapCount, 0);
  });
}

Widget _refreshTestApp({
  required Future<void> Function() onRefresh,
  required List<Widget> children,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeFeedRefreshSurface(
        onRefresh: onRefresh,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: children,
        ),
      ),
    ),
  );
}
