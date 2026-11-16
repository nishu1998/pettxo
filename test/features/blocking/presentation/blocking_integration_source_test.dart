import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'profile exposes safety actions and hides ordinary blocked interactions',
    () {
      final source = File(
        'lib/features/profile/presentation/screens/profile_screen.dart',
      ).readAsStringSync();

      expect(source, contains("'Report User'"));
      expect(source, contains("'Blocked'"));
      expect(source, contains('relationshipBlocked ||'));
      expect(source, contains('_updateBlockState'));
    },
  );

  test(
    'chat keeps history while disabling text, image, and retry controls',
    () {
      final source = File(
        'lib/features/messages/presentation/screens/chat_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_repository.watchRecentMessageSnapshots'));
      expect(source, contains('_imageMessagingEnabled && !interactionBlocked'));
      expect(source, contains('!interactionBlocked &&'));
      expect(source, contains('interactionBlocked ? null : _retryImageSend'));
      expect(source, contains('conversation history remains available'));
    },
  );

  test('blocking changes invalidate every normal discovery surface', () {
    final expectations = <String, String>{
      'lib/features/home/presentation/screens/home_screen.dart':
          '_refreshHome()',
      'lib/features/explore/presentation/screens/explore_screen.dart':
          '_refreshExploreSections()',
      'lib/features/services/presentation/screens/services_screen.dart':
          'setState(_refreshServicesStream)',
      'lib/features/messages/presentation/screens/messages_screen.dart':
          '_refreshMessages()',
      'lib/features/social/presentation/screens/user_list_screen.dart':
          '_loadInitialPage()',
      'lib/features/social/presentation/widgets/comment_sheet.dart':
          '_loadInitialComments()',
    };
    for (final entry in expectations.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(source, contains('BlockingChangeCoordinator.instance.changes'));
      expect(source, contains(entry.value));
    }
  });

  test('profile and chat use the secured user report callable schema', () {
    final reportSource = File(
      'lib/features/moderation/data/repositories/report_repository.dart',
    ).readAsStringSync();
    final safetySource = File(
      'lib/features/blocking/presentation/user_safety_dialogs.dart',
    ).readAsStringSync();

    expect(reportSource, contains("normalizedType != 'user'"));
    expect(safetySource, contains("type: 'user'"));
    expect(safetySource, contains('ReportSheet.show'));
  });

  test(
    'no blocking UI writes directly to Firestore relationship documents',
    () {
      final sources = Directory('lib/features/blocking')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(sources, isNot(contains("collection('userRelationshipGuards')")));
      expect(sources, isNot(contains("collection('userBlocks').add")));
      expect(sources, isNot(contains('transaction.set')));
      expect(sources, isNot(contains('.set(')));
      expect(sources, contains("httpsCallable(callableName)"));
    },
  );
}
