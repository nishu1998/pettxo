import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/data/services/post_publish_coordinator.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  group('PostPublishDraft media recovery', () {
    test('restores retained source paths and formats for recropping', () {
      const draft = PostPublishDraft(
        imagePaths: <String>['/managed/prepared.jpg'],
        sourceImagePaths: <String>['/managed/source.png'],
        sourceFormats: <String>['png'],
        aspectRatio: SocialPostAspectRatio.square,
        caption: 'Caption',
        hashtags: <String>['pets'],
        includeLocation: false,
      );

      final media = draft.toMedia();

      expect(media, hasLength(1));
      expect(media.single.prepared.path, '/managed/prepared.jpg');
      expect(media.single.source.path, '/managed/source.png');
      expect(media.single.sourceFormat, 'png');
    });

    test('falls back to the prepared JPEG for legacy drafts', () {
      const draft = PostPublishDraft(
        imagePaths: <String>['/managed/prepared.jpg'],
        aspectRatio: SocialPostAspectRatio.portrait,
        caption: '',
        hashtags: <String>[],
        includeLocation: false,
      );

      final media = draft.toMedia();

      expect(media.single.source.path, '/managed/prepared.jpg');
      expect(media.single.sourceFormat, 'jpeg');
    });
  });
}
