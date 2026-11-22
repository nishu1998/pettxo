import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/data/social_post_repository.dart';
import 'package:pettexo/features/social/domain/models/comment_model.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';
import 'package:pettexo/features/social/presentation/widgets/comment_sheet.dart';

const _me = 'alice';
const _rawFirestoreText = 'cloud_firestore/permission-denied';

FirebaseException _permissionDenied() => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
  message:
      'The caller does not have permission to execute the specified operation.',
);

CommentModel _comment({required String authorId}) => CommentModel(
  id: 'c1',
  postId: 'p1',
  authorId: authorId,
  authorDisplayName: authorId,
  authorUsername: authorId,
  authorPhotoUrl: '',
  parentPostAuthorId: 'bob',
  parentPostPreview: 'hello',
  text: 'a comment',
  likeCount: 0,
  reportCount: 0,
  visibilityStatus: 'visible',
  moderationStatus: 'approved',
  moderationReason: '',
  moderatedBy: '',
  moderatedAt: null,
  lastReportedAt: null,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  updatedAt: Timestamp.fromMillisecondsSinceEpoch(0),
);

class _FakeSocialPostRepository implements SocialPostRepository {
  _FakeSocialPostRepository({this.comments = const <CommentModel>[]});

  final List<CommentModel> comments;
  Object? addCommentError;
  Object? deleteError;
  Object? reportError;

  @override
  Future<CommentPage> fetchComments({
    required String postId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 10,
  }) async {
    return CommentPage(comments: comments, lastDocument: null, hasMore: false);
  }

  @override
  Future<CommentModel> addComment({
    required String postId,
    required String currentUserId,
    required String text,
  }) async {
    throw addCommentError!;
  }

  @override
  Future<void> softDeleteComment({
    required String postId,
    required String commentId,
    required String currentUserId,
  }) async {
    throw deleteError!;
  }

  @override
  Future<bool> reportComment({
    required String postId,
    required String commentId,
    required String currentUserId,
    required String reason,
  }) async {
    throw reportError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Like setupFirebaseCoreMocks(), but the default app has a storage bucket so
/// FirebaseStorage.instance (constructed eagerly by ProfileRepository) works.
class _FirebaseCoreMockWithBucket implements TestFirebaseCoreHostApi {
  static CoreFirebaseOptions get _options => CoreFirebaseOptions(
    apiKey: 'test-api-key',
    projectId: 'demo-pettexo-widget-test',
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    storageBucket: 'demo-pettexo-widget-test.appspot.com',
  );

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: _options,
      pluginConstants: {},
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    return [
      CoreInitializeResponse(
        name: defaultFirebaseAppName,
        options: _options,
        pluginConstants: {},
      ),
    ];
  }

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async => _options;
}

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakeSocialPostRepository repository,
) async {
  final post = SocialPostModel.fromMap(const <String, dynamic>{
    'id': 'p1',
    'authorId': 'bob',
    'caption': 'hello',
    'visibilityStatus': 'visible',
    'moderationStatus': 'approved',
    'commentCount': 1,
  }, fallbackId: 'p1');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CommentSheet(
          post: post,
          currentUserId: _me,
          repository: repository,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(_FirebaseCoreMockWithBucket());

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('posting: permission-denied shows the friendly message', (
    tester,
  ) async {
    final repository = _FakeSocialPostRepository()
      ..addCommentError = _permissionDenied();
    await _pumpSheet(tester, repository);

    await tester.enterText(find.byType(TextField), 'nice post');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text("You can't comment on this post right now."),
      findsOneWidget,
    );
    expect(find.textContaining(_rawFirestoreText), findsNothing);
  });

  testWidgets('deleting: permission-denied shows the friendly message', (
    tester,
  ) async {
    final repository = _FakeSocialPostRepository(
      comments: [_comment(authorId: _me)],
    )..deleteError = _permissionDenied();
    await _pumpSheet(tester, repository);

    await tester.longPress(find.text('a comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text("You can't delete this comment right now."),
      findsOneWidget,
    );
    expect(find.textContaining(_rawFirestoreText), findsNothing);
  });

  testWidgets('reporting: permission-denied shows the friendly message', (
    tester,
  ) async {
    final repository = _FakeSocialPostRepository(
      comments: [_comment(authorId: 'bob')],
    )..reportError = _permissionDenied();
    await _pumpSheet(tester, repository);

    await tester.longPress(find.text('a comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text("You can't report this comment right now."),
      findsOneWidget,
    );
    expect(find.textContaining(_rawFirestoreText), findsNothing);
  });
}
