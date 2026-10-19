import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pettexo/core/widgets/social_bottom_nav.dart';
import 'package:pettexo/features/social/application/social_post_media_preparation_service.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';
import 'package:pettexo/features/social/presentation/screens/create_post_screen.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('composer-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('ratio switch is transactional and preserves caption', (
    tester,
  ) async {
    final initial = _media(root, 'initial');
    final replacement = _media(root, 'portrait');
    final service = _RecropService(
      SocialPostMediaRecropResult.success(<SocialPostPreparedMedia>[
        replacement,
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePostScreen(
          initialMedia: <SocialPostPreparedMedia>[initial],
          preparationService: service,
          checkRestrictions: false,
          restoreRecoverableDraft: false,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Caption stays here');

    _invokeRatio(tester, 'Portrait 4:5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(service.recropCalls, 1);
    expect(service.lastRatio, SocialPostAspectRatio.portrait);
    expect(service.lastSources.single, initial.source.path);
    expect(find.text('Caption stays here'), findsOneWidget);
    expect(find.text('Remove selected images'), findsNothing);
  });

  testWidgets('composer reflects the ratio selected by the first crop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePostScreen(
          initialMedia: <SocialPostPreparedMedia>[_media(root, 'portrait')],
          initialAspectRatio: SocialPostAspectRatio.portrait,
          checkRestrictions: false,
          restoreRecoverableDraft: false,
        ),
      ),
    );

    expect(_ratioSemantics(tester, 'Portrait 4:5').properties.selected, isTrue);
    expect(_ratioSemantics(tester, 'Square 1:1').properties.selected, isFalse);
  });

  testWidgets('Add Photos cancellation preserves the existing draft', (
    tester,
  ) async {
    final service = _AddPhotoCancellationService();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePostScreen(
          initialMedia: <SocialPostPreparedMedia>[_media(root, 'existing')],
          initialAspectRatio: SocialPostAspectRatio.portrait,
          preparationService: service,
          checkRestrictions: false,
          restoreRecoverableDraft: false,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Keep this draft');

    final addPhotos = find.byIcon(Icons.add_photo_alternate_outlined);
    await tester.ensureVisible(addPhotos);
    await tester.tap(addPhotos);
    await tester.pumpAndSettle();

    expect(service.lastRatio, SocialPostAspectRatio.portrait);
    expect(find.text('PHOTOS · 1/5'), findsOneWidget);
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(_ratioSemantics(tester, 'Portrait 4:5').properties.selected, isTrue);
  });

  testWidgets('duplicate ratio taps are blocked while recropping', (
    tester,
  ) async {
    final initial = _media(root, 'initial');
    final replacement = _media(root, 'portrait');
    final completer = Completer<SocialPostMediaRecropResult>();
    final service = _RecropService.pending(completer);
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePostScreen(
          initialMedia: <SocialPostPreparedMedia>[initial],
          preparationService: service,
          checkRestrictions: false,
          restoreRecoverableDraft: false,
        ),
      ),
    );

    _invokeRatio(tester, 'Portrait 4:5');
    await tester.pump();
    _invokeRatio(tester, 'Portrait 4:5');
    expect(service.recropCalls, 1);

    completer.complete(
      SocialPostMediaRecropResult.success(<SocialPostPreparedMedia>[
        replacement,
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  for (final size in <Size>[
    const Size(360, 640),
    const Size(393, 852),
    const Size(412, 915),
  ]) {
    testWidgets(
      'full-screen composer has no tab nav at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final initial = _media(root, 'layout-${size.width}');

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.3),
                viewPadding: const EdgeInsets.only(bottom: 24),
              ),
              child: CreatePostScreen(
                initialMedia: <SocialPostPreparedMedia>[initial],
                checkRestrictions: false,
                restoreRecoverableDraft: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(SocialBottomNav), findsNothing);
        expect(find.text('Share'), findsOneWidget);
        expect(
          find.byIcon(Icons.add_photo_alternate_outlined, skipOffstage: false),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyboard inset keeps header and scrollable composer available', (
    tester,
  ) async {
    final initial = _media(root, 'keyboard');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            viewInsets: EdgeInsets.only(bottom: 300),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: CreatePostScreen(
            initialMedia: <SocialPostPreparedMedia>[initial],
            checkRestrictions: false,
            restoreRecoverableDraft: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Share'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(SocialBottomNav), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android-style back returns from dedicated composer route', (
    tester,
  ) async {
    final initial = _media(root, 'back');
    await tester.pumpWidget(
      MaterialApp(
        home: const Text('Home'),
        routes: <String, WidgetBuilder>{
          '/composer': (_) => CreatePostScreen(
            initialMedia: <SocialPostPreparedMedia>[initial],
            checkRestrictions: false,
            restoreRecoverableDraft: false,
          ),
        },
      ),
    );
    Navigator.of(tester.element(find.text('Home'))).pushNamed('/composer');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}

void _invokeRatio(WidgetTester tester, String label) {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  tester.widget<InkWell>(finder.first).onTap!.call();
}

Semantics _ratioSemantics(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .singleWhere((widget) => widget.properties.label == label);
}

class _RecropService extends SocialPostMediaPreparationService {
  _RecropService(this.result) : pending = null;
  _RecropService.pending(this.pending) : result = null;

  final SocialPostMediaRecropResult? result;
  final Completer<SocialPostMediaRecropResult>? pending;
  int recropCalls = 0;
  SocialPostAspectRatio? lastRatio;
  List<String> lastSources = const <String>[];

  @override
  Future<SocialPostMediaRecropResult> recropPreparedMedia({
    required List<SocialPostPreparedMedia> current,
    required SocialPostAspectRatio aspectRatio,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) {
    recropCalls += 1;
    lastRatio = aspectRatio;
    lastSources = current.map((item) => item.source.path).toList();
    return pending?.future ?? Future.value(result!);
  }
}

class _AddPhotoCancellationService extends SocialPostMediaPreparationService {
  SocialPostAspectRatio? lastRatio;

  @override
  Future<SocialPostMediaPreparationResult> pickCropAndPrepare({
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    lastRatio = aspectRatio;
    return const SocialPostMediaPreparationResult(
      galleryCancelled: false,
      cropCancellationCount: 1,
      optimizedCount: 0,
      selectionTruncated: false,
    );
  }
}

SocialPostPreparedMedia _media(Directory root, String name) {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(20, 40, 60));
  final source = File('${root.path}/$name-source.jpg');
  final prepared = File('${root.path}/$name-prepared.jpg');
  final bytes = img.encodeJpg(image);
  source.writeAsBytesSync(bytes);
  prepared.writeAsBytesSync(bytes);
  return SocialPostPreparedMedia(
    source: XFile(source.path),
    prepared: XFile(prepared.path),
    sourceFormat: 'jpeg',
  );
}
