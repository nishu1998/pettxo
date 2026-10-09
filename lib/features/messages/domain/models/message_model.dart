import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String type;
  final DateTime? createdAt;
  final List<String> deliveredTo;
  final List<String> readBy;
  final String sourceServiceId;
  final String sourceServiceTitle;
  final String storagePath;
  final int imageWidth;
  final int imageHeight;
  final int imageSizeBytes;
  final String mimeType;
  final int mediaSchemaVersion;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.type,
    required this.createdAt,
    required this.deliveredTo,
    required this.readBy,
    required this.sourceServiceId,
    required this.sourceServiceTitle,
    this.storagePath = '',
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.imageSizeBytes = 0,
    this.mimeType = '',
    this.mediaSchemaVersion = 0,
  });

  factory MessageModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return MessageModel.fromMap(
      doc.id,
      doc.data() ?? const <String, dynamic>{},
    );
  }

  factory MessageModel.fromMap(String id, Map<String, dynamic> data) {
    return MessageModel(
      id: id,
      senderId: (data['senderId'] as String? ?? '').trim(),
      receiverId: (data['receiverId'] as String? ?? '').trim(),
      text: (data['text'] as String? ?? '').trim(),
      type: (data['type'] as String? ?? 'text').trim(),
      createdAt: _readDate(data['createdAt']),
      deliveredTo: (data['deliveredTo'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      readBy: (data['readBy'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      sourceServiceId: (data['sourceServiceId'] as String? ?? '').trim(),
      sourceServiceTitle: (data['sourceServiceTitle'] as String? ?? '').trim(),
      storagePath: (data['storagePath'] as String? ?? '').trim(),
      imageWidth: (data['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (data['imageHeight'] as num?)?.toInt() ?? 0,
      imageSizeBytes: (data['imageSizeBytes'] as num?)?.toInt() ?? 0,
      mimeType: (data['mimeType'] as String? ?? '').trim(),
      mediaSchemaVersion: (data['mediaSchemaVersion'] as num?)?.toInt() ?? 0,
    );
  }

  bool isSentBy(String uid) => senderId == uid.trim();

  bool get isText => type.isEmpty || type == 'text';

  bool get isImage =>
      type == 'image' &&
      storagePath.isNotEmpty &&
      imageWidth > 0 &&
      imageHeight > 0;

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
