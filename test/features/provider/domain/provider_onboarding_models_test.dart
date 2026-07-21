import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/provider/domain/models/provider_onboarding_models.dart';

void main() {
  test(
    'provider verification prefers private storage paths and keeps PAN front-only semantics',
    () {
      final record = ProviderVerificationRecord.fromMap('uid_123', {
        'userId': 'uid_123',
        'status': 'pending',
        'documentType': 'panCard',
        'documentFrontPath': 'providerVerification/uid_123/identity/front.pdf',
        'documentBackPath': '',
        'documentFrontUrl': 'https://legacy.example/front.pdf',
        'documentBackUrl': 'https://legacy.example/back.pdf',
        'documentFrontContentType': 'application/pdf',
        'documentBackContentType': '',
        'documentFrontFileName': 'pan.pdf',
        'documentBackFileName': '',
        'verificationMethod': 'manual',
      });

      expect(record.isPanCard, isTrue);
      expect(record.hasFrontDocument, isTrue);
      expect(record.hasBackDocument, isTrue);
      expect(
        record.preferredFrontDocumentLocation,
        'providerVerification/uid_123/identity/front.pdf',
      );
      expect(
        record.preferredBackDocumentLocation,
        'https://legacy.example/back.pdf',
      );
      expect(record.usesPrivateStoragePaths, isTrue);
      expect(record.frontDocumentIsPdf, isTrue);
      expect(record.documentTypeLabel, 'PAN Card');
    },
  );

  test('provider verification falls back to legacy urls for older records', () {
    final record = ProviderVerificationRecord.fromMap('uid_123', {
      'userId': 'uid_123',
      'status': 'rejected',
      'documentType': 'aadhaar',
      'documentFrontUrl': 'https://legacy.example/front.jpg',
      'documentBackUrl': '',
    });

    expect(record.hasFrontDocument, isTrue);
    expect(record.hasBackDocument, isFalse);
    expect(
      record.preferredFrontDocumentLocation,
      'https://legacy.example/front.jpg',
    );
    expect(record.canResubmit, isTrue);
    expect(record.documentTypeLabel, 'Aadhaar Card');
  });
}
