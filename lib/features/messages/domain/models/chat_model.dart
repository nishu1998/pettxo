import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String id;
  final String customerId;
  final String providerId;
  final List<String> participantIds;
  final String customerName;
  final String customerPhotoUrl;
  final String providerName;
  final String providerPhotoUrl;
  final List<String> sourceServiceIds;
  final String lastServiceId;
  final String lastServiceTitle;
  final String lastServiceImageUrl;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String lastSenderId;
  final int unreadCountCustomer;
  final int unreadCountProvider;
  final DateTime? customerLastReadAt;
  final DateTime? providerLastReadAt;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ChatModel({
    required this.id,
    required this.customerId,
    required this.providerId,
    required this.participantIds,
    required this.customerName,
    required this.customerPhotoUrl,
    required this.providerName,
    required this.providerPhotoUrl,
    required this.sourceServiceIds,
    required this.lastServiceId,
    required this.lastServiceTitle,
    required this.lastServiceImageUrl,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastSenderId,
    required this.unreadCountCustomer,
    required this.unreadCountProvider,
    required this.customerLastReadAt,
    required this.providerLastReadAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ChatModel.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  factory ChatModel.fromMap(String id, Map<String, dynamic> data) {
    return ChatModel(
      id: id,
      customerId: (data['customerId'] as String? ?? '').trim(),
      providerId: (data['providerId'] as String? ?? '').trim(),
      participantIds: (data['participantIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      customerName: (data['customerName'] as String? ?? '').trim(),
      customerPhotoUrl: (data['customerPhotoUrl'] as String? ?? '').trim(),
      providerName: (data['providerName'] as String? ?? '').trim(),
      providerPhotoUrl: (data['providerPhotoUrl'] as String? ?? '').trim(),
      sourceServiceIds: (data['sourceServiceIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      lastServiceId: (data['lastServiceId'] as String? ?? '').trim(),
      lastServiceTitle: (data['lastServiceTitle'] as String? ?? '').trim(),
      lastServiceImageUrl: (data['lastServiceImageUrl'] as String? ?? '')
          .trim(),
      lastMessage: (data['lastMessage'] as String? ?? '').trim(),
      lastMessageAt: _readDate(data['lastMessageAt']),
      lastSenderId: (data['lastSenderId'] as String? ?? '').trim(),
      unreadCountCustomer: (data['unreadCountCustomer'] as num?)?.toInt() ?? 0,
      unreadCountProvider: (data['unreadCountProvider'] as num?)?.toInt() ?? 0,
      customerLastReadAt: _readDate(data['customerLastReadAt']),
      providerLastReadAt: _readDate(data['providerLastReadAt']),
      status: (data['status'] as String? ?? 'active').trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  String otherParticipantIdFor(String currentUid) {
    final trimmedUid = currentUid.trim();
    if (trimmedUid == customerId) return providerId;
    if (trimmedUid == providerId) return customerId;
    return participantIds.firstWhere(
      (value) => value != trimmedUid,
      orElse: () => '',
    );
  }

  String otherParticipantNameFor(String currentUid) {
    return currentUid.trim() == customerId
        ? providerDisplayName
        : customerDisplayName;
  }

  String otherParticipantPhotoUrlFor(String currentUid) {
    return currentUid.trim() == customerId
        ? providerPhotoUrl
        : customerPhotoUrl;
  }

  int unreadCountFor(String currentUid) {
    if (currentUid.trim() == customerId) return unreadCountCustomer;
    if (currentUid.trim() == providerId) return unreadCountProvider;
    return 0;
  }

  String get customerDisplayName =>
      customerName.isEmpty ? 'Customer' : customerName;

  String get providerDisplayName =>
      providerName.isEmpty ? 'Service Provider' : providerName;

  bool get isClosed => status == 'closed';

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
