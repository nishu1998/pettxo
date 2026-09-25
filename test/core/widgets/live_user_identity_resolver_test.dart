import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/live_user_identity_resolver.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';

void main() {
  testWidgets('adjacent keyed authors keep their identities after reordering', (
    tester,
  ) async {
    final streams = <String, StreamController<UserProfile>>{
      'author-a': StreamController<UserProfile>.broadcast(),
      'author-b': StreamController<UserProfile>.broadcast(),
    };

    Widget build(List<({String postId, String authorId})> posts) {
      return MaterialApp(
        home: Column(
          children: posts
              .map(
                (item) => LiveUserIdentityResolver(
                  key: ValueKey<String>(item.postId),
                  userId: item.authorId,
                  fallbackName: 'Fallback ${item.authorId}',
                  fallbackUsername: item.authorId,
                  fallbackImageUrl: '',
                  profileStreamFactory: (uid) => streams[uid]!.stream,
                  initialProfileProvider: (_) => null,
                  builder: (_, identity) =>
                      Text('${item.postId}:${identity.displayName}'),
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    await tester.pumpWidget(
      build(const [
        (postId: 'post-a', authorId: 'author-a'),
        (postId: 'post-b', authorId: 'author-b'),
      ]),
    );
    streams['author-a']!.add(_profile('author-a', 'Alice'));
    streams['author-b']!.add(_profile('author-b', 'Bob'));
    await tester.pump();

    await tester.pumpWidget(
      build(const [
        (postId: 'post-b', authorId: 'author-b'),
        (postId: 'post-a', authorId: 'author-a'),
      ]),
    );
    await tester.pump();

    expect(find.text('post-a:Alice'), findsOneWidget);
    expect(find.text('post-b:Bob'), findsOneWidget);

    for (final controller in streams.values) {
      await controller.close();
    }
  });

  testWidgets('an old author response cannot update a rebound resolver', (
    tester,
  ) async {
    final authorA = StreamController<UserProfile>.broadcast();
    final authorB = StreamController<UserProfile>.broadcast();
    final streams = <String, Stream<UserProfile>>{
      'author-a': authorA.stream,
      'author-b': authorB.stream,
    };

    Widget build(String authorId) {
      return MaterialApp(
        home: LiveUserIdentityResolver(
          userId: authorId,
          fallbackName: 'Fallback $authorId',
          fallbackUsername: authorId,
          fallbackImageUrl: '',
          profileStreamFactory: (uid) => streams[uid]!,
          initialProfileProvider: (_) => null,
          builder: (_, identity) => Text(identity.displayName),
        ),
      );
    }

    await tester.pumpWidget(build('author-a'));
    authorA.add(_profile('author-a', 'Alice'));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);

    await tester.pumpWidget(build('author-b'));
    await tester.pump();
    expect(find.text('Fallback author-b'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    authorA.add(_profile('author-a', 'Wrong stale author'));
    await tester.pump();
    expect(find.text('Wrong stale author'), findsNothing);
    expect(find.text('Fallback author-b'), findsOneWidget);

    authorB.add(_profile('author-b', 'Bob'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Bob'), findsOneWidget);

    await authorA.close();
    await authorB.close();
  });
}

UserProfile _profile(String uid, String name) {
  return UserProfile.fromMap(<String, dynamic>{
    'uid': uid,
    'displayName': name,
    'username': name.toLowerCase(),
  });
}
