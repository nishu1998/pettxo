import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pettexo/features/social/application/social_post_media_preparation_service.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';
import 'package:pettexo/features/social/presentation/screens/create_post_flow_screen.dart';

void main() {
  late Directory directory;

  setUp(() async {
    CreatePostFlowLauncher.resetForTesting();
    directory = await Directory.systemTemp.createTemp('create-post-flow-');
  });

  tearDown(() async {
    CreatePostFlowLauncher.resetForTesting();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('gallery cancellation returns without opening composer', (
    tester,
  ) async {
    final service = _FakePreparationService(
      const SocialPostMediaPreparationResult(
        images: <XFile>[],
        galleryCancelled: true,
        cropCancellationCount: 0,
        failureCount: 0,
        oversizedFailureCount: 0,
        optimizedCount: 0,
        selectionTruncated: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: const Text('Previous screen'),
        routes: <String, WidgetBuilder>{
          '/create': (_) => CreatePostFlowScreen(
            preparationService: service,
            checkRestrictions: false,
            hasRecoverableDraft: () => false,
            composerBuilder: (_) => const Text('Composer'),
          ),
        },
      ),
    );

    Navigator.of(
      tester.element(find.text('Previous screen')),
    ).pushNamed('/create');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Previous screen'), findsOneWidget);
    expect(find.text('Composer'), findsNothing);
  });

  testWidgets('prepared images populate the composer in selection order', (
    tester,
  ) async {
    final service = _FakePreparationService(
      SocialPostMediaPreparationResult(
        images: <XFile>[XFile('/tmp/first.jpg'), XFile('/tmp/second.jpg')],
        galleryCancelled: false,
        cropCancellationCount: 0,
        failureCount: 0,
        oversizedFailureCount: 0,
        optimizedCount: 0,
        selectionTruncated: false,
        selectedAspectRatio: SocialPostAspectRatio.portrait,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePostFlowScreen(
          preparationService: service,
          checkRestrictions: false,
          hasRecoverableDraft: () => false,
          composerBuilder: (images) => Text(
            'Composer:${images.length}:${images[0].path != images[1].path}',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Composer:2:true'), findsOneWidget);
    expect(find.text('Choose photo shape'), findsNothing);
    expect(service.lastAspectRatio, SocialPostAspectRatio.square);
    expect(service.allowedFirstCropRatioSelection, isTrue);
    expect(service.transactionalBatch, isTrue);
  });

  testWidgets('first crop cancellation returns without a sheet or composer', (
    tester,
  ) async {
    final picked = File('${directory.path}/picked.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final service = _FakePreparationService(
      const SocialPostMediaPreparationResult(
        galleryCancelled: false,
        cropCancellationCount: 1,
        optimizedCount: 0,
        selectionTruncated: false,
      ),
      picked: <XFile>[XFile(picked.path)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: const Text('Previous screen'),
        routes: <String, WidgetBuilder>{
          '/create': (_) => CreatePostFlowScreen(
            preparationService: service,
            checkRestrictions: false,
            hasRecoverableDraft: () => false,
            composerBuilder: (_) => const Text('Composer'),
          ),
        },
      ),
    );

    Navigator.of(
      tester.element(find.text('Previous screen')),
    ).pushNamed('/create');
    await tester.pumpAndSettle();

    expect(find.text('Previous screen'), findsOneWidget);
    expect(find.text('Choose photo shape'), findsNothing);
    expect(find.text('Image cropping was cancelled.'), findsNothing);
    expect(find.text('Composer'), findsNothing);
  });

  testWidgets('preparation loader is hidden while native cropper is active', (
    tester,
  ) async {
    final service = _CroppingStagePreparationService();
    await tester.pumpWidget(
      MaterialApp(
        home: const Text('Previous screen'),
        routes: <String, WidgetBuilder>{
          '/create': (_) => CreatePostFlowScreen(
            preparationService: service,
            checkRestrictions: false,
            hasRecoverableDraft: () => false,
          ),
        },
      ),
    );

    Navigator.of(
      tester.element(find.text('Previous screen')),
    ).pushNamed('/create');
    await tester.pump();
    await service.cropperOpened.future;
    await tester.pump();

    expect(
      find.byKey(const Key('create-post-preparation-loader')),
      findsNothing,
    );

    service.finishCrop.complete();
    await tester.pumpAndSettle();
    expect(find.text('Previous screen'), findsOneWidget);
  });

  testWidgets('rapid launcher taps push only one gallery route', (
    tester,
  ) async {
    var routeBuildCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              unawaited(
                CreatePostFlowLauncher.open(context, checkRestrictions: false),
              );
            },
            child: const Text('Create'),
          ),
        ),
        routes: <String, WidgetBuilder>{
          '/create': (_) {
            routeBuildCount += 1;
            return const Scaffold(body: Text('Gallery route'));
          },
        },
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(routeBuildCount, 1);
    expect(find.text('Gallery route'), findsOneWidget);
  });
}

class _FakePreparationService extends SocialPostMediaPreparationService {
  _FakePreparationService(this.result, {this.picked});

  final SocialPostMediaPreparationResult result;
  final List<XFile>? picked;
  SocialPostAspectRatio? lastAspectRatio;
  bool? allowedFirstCropRatioSelection;
  bool? transactionalBatch;

  @override
  Future<List<XFile>> pickGalleryImages() async =>
      result.galleryCancelled ? const <XFile>[] : picked ?? result.images;

  @override
  Future<SocialPostMediaPreparationResult> preparePickedImages({
    required List<XFile> picked,
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
    bool allowFirstCropRatioSelection = false,
    bool transactionalBatch = false,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    lastAspectRatio = aspectRatio;
    allowedFirstCropRatioSelection = allowFirstCropRatioSelection;
    this.transactionalBatch = transactionalBatch;
    return result;
  }
}

class _CroppingStagePreparationService
    extends SocialPostMediaPreparationService {
  final Completer<void> cropperOpened = Completer<void>();
  final Completer<void> finishCrop = Completer<void>();

  @override
  Future<List<XFile>> pickGalleryImages() async => <XFile>[
    XFile('/picked.jpg'),
  ];

  @override
  Future<SocialPostMediaPreparationResult> preparePickedImages({
    required List<XFile> picked,
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
    bool allowFirstCropRatioSelection = false,
    bool transactionalBatch = false,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    onStageChanged?.call(SocialPostMediaPreparationStage.cropping);
    cropperOpened.complete();
    await finishCrop.future;
    onStageChanged?.call(SocialPostMediaPreparationStage.idle);
    return const SocialPostMediaPreparationResult(
      galleryCancelled: false,
      cropCancellationCount: 1,
      optimizedCount: 0,
      selectionTruncated: false,
    );
  }
}
