import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/utils/social_post_share.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  test('builds branded Pettxo share text without media URLs', () {
    final post = SocialPostModel.fromMap({
      'id': 'post123',
      'authorId': 'author123',
      'authorDisplayName': 'Mabel',
      'caption': 'Hyy Toby 🦊',
      'imageUrls': ['https://firebasestorage.googleapis.com/example'],
      'thumbnailUrls': <String>[],
      'hashtags': ['pets'],
    });

    final text = buildSocialPostShareText(post);

    expect(text, contains('🐾 Check out this post on Pettxo'));
    expect(text, contains('Mabel'));
    expect(text, contains('Hyy Toby 🦊'));
    expect(text, contains('https://pettxo.com/post/post123'));
    expect(text, isNot(contains('firebasestorage.googleapis.com')));
  });

  test('parses Pettxo social post app links safely', () {
    expect(
      tryParseSocialPostIdFromUri(Uri.parse('https://pettxo.com/post/post123')),
      'post123',
    );
    expect(
      tryParseSocialPostIdFromUri(
        Uri.parse('https://pettxo.com/post/post123?ref=whatsapp'),
      ),
      'post123',
    );
    expect(
      tryParseSocialPostIdFromUri(
        Uri.parse('https://pettxo.com/profile/post123'),
      ),
      isNull,
    );
  });
}
