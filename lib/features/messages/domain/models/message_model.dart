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
    );
  }

  bool isSentBy(String uid) => senderId == uid.trim();

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
