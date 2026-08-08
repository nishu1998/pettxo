import 'package:cloud_firestore/cloud_firestore.dart';

enum SupportTicketCategory {
  booking,
  payment,
  refund,
  account,
  provider,
  safety,
  technicalIssue,
  other,
}

extension SupportTicketCategoryX on SupportTicketCategory {
  String get value {
    switch (this) {
      case SupportTicketCategory.booking:
        return 'booking';
      case SupportTicketCategory.payment:
        return 'payment';
      case SupportTicketCategory.refund:
        return 'refund';
      case SupportTicketCategory.account:
        return 'account';
      case SupportTicketCategory.provider:
        return 'provider';
      case SupportTicketCategory.safety:
        return 'safety';
      case SupportTicketCategory.technicalIssue:
        return 'technical_issue';
      case SupportTicketCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case SupportTicketCategory.booking:
        return 'Booking';
      case SupportTicketCategory.payment:
        return 'Payment';
      case SupportTicketCategory.refund:
        return 'Refund';
      case SupportTicketCategory.account:
        return 'Account';
      case SupportTicketCategory.provider:
        return 'Provider';
      case SupportTicketCategory.safety:
        return 'Safety';
      case SupportTicketCategory.technicalIssue:
        return 'Technical issue';
      case SupportTicketCategory.other:
        return 'Other';
    }
  }

  static SupportTicketCategory parse(String raw) {
    switch (raw.trim()) {
      case 'booking':
        return SupportTicketCategory.booking;
      case 'payment':
        return SupportTicketCategory.payment;
      case 'refund':
        return SupportTicketCategory.refund;
      case 'account':
        return SupportTicketCategory.account;
      case 'provider':
        return SupportTicketCategory.provider;
      case 'safety':
        return SupportTicketCategory.safety;
      case 'technical_issue':
        return SupportTicketCategory.technicalIssue;
      default:
        return SupportTicketCategory.other;
    }
  }
}

enum SupportTicketStatus { open, awaitingSupport, awaitingCustomer, resolved }

extension SupportTicketStatusX on SupportTicketStatus {
  String get value {
    switch (this) {
      case SupportTicketStatus.open:
        return 'open';
      case SupportTicketStatus.awaitingSupport:
        return 'awaiting_support';
      case SupportTicketStatus.awaitingCustomer:
        return 'awaiting_customer';
      case SupportTicketStatus.resolved:
        return 'resolved';
    }
  }

  String get label {
    switch (this) {
      case SupportTicketStatus.open:
        return 'Open';
      case SupportTicketStatus.awaitingSupport:
        return 'Awaiting support';
      case SupportTicketStatus.awaitingCustomer:
        return 'Awaiting your reply';
      case SupportTicketStatus.resolved:
        return 'Resolved';
    }
  }

  static SupportTicketStatus parse(String raw) {
    switch (raw.trim()) {
      case 'awaiting_support':
        return SupportTicketStatus.awaitingSupport;
      case 'awaiting_customer':
        return SupportTicketStatus.awaitingCustomer;
      case 'resolved':
        return SupportTicketStatus.resolved;
      default:
        return SupportTicketStatus.open;
    }
  }
}

enum SupportMessageSenderType { customer, admin }

extension SupportMessageSenderTypeX on SupportMessageSenderType {
  String get value {
    switch (this) {
      case SupportMessageSenderType.customer:
        return 'customer';
      case SupportMessageSenderType.admin:
        return 'admin';
    }
  }

  static SupportMessageSenderType parse(String raw) {
    switch (raw.trim()) {
      case 'admin':
        return SupportMessageSenderType.admin;
      default:
        return SupportMessageSenderType.customer;
    }
  }
}

DateTime? _timestampToDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return null;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.category,
    required this.subject,
    required this.initialMessage,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.lastMessageSenderType,
    required this.customerUnreadCount,
    required this.adminUnreadCount,
    required this.userDisplayName,
    required this.username,
    required this.contactNumber,
    required this.attachments,
  });

  factory SupportTicket.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SupportTicket(
      id: snapshot.id,
      ticketId: '${data['ticketId'] ?? snapshot.id}'.trim(),
      userId: '${data['userId'] ?? ''}'.trim(),
      category: SupportTicketCategoryX.parse('${data['category'] ?? ''}'),
      subject: '${data['subject'] ?? ''}'.trim(),
      initialMessage: '${data['initialMessage'] ?? ''}'.trim(),
      status: SupportTicketStatusX.parse('${data['status'] ?? ''}'),
      createdAt: _timestampToDate(data['createdAt']),
      updatedAt: _timestampToDate(data['updatedAt']),
      lastMessageAt: _timestampToDate(data['lastMessageAt']),
      lastMessagePreview: '${data['lastMessagePreview'] ?? ''}'.trim(),
      lastMessageSenderType: SupportMessageSenderTypeX.parse(
        '${data['lastMessageSenderType'] ?? ''}',
      ),
      customerUnreadCount: (data['customerUnreadCount'] as num?)?.toInt() ?? 0,
      adminUnreadCount: (data['adminUnreadCount'] as num?)?.toInt() ?? 0,
      userDisplayName: '${data['userDisplayName'] ?? ''}'.trim(),
      username: '${data['username'] ?? ''}'.trim(),
      contactNumber: '${data['contactNumber'] ?? ''}'.trim(),
      attachments: ((data['attachments'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (item) => SupportTicketAttachment.fromMap(
              Map<String, dynamic>.from(item.cast<String, dynamic>()),
            ),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String ticketId;
  final String userId;
  final SupportTicketCategory category;
  final String subject;
  final String initialMessage;
  final SupportTicketStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final SupportMessageSenderType lastMessageSenderType;
  final int customerUnreadCount;
  final int adminUnreadCount;
  final String userDisplayName;
  final String username;
  final String contactNumber;
  final List<SupportTicketAttachment> attachments;

  bool get hasUnreadAdminReply => customerUnreadCount > 0;
}

class SupportTicketAttachment {
  const SupportTicketAttachment({
    required this.attachmentId,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.createdAt,
  });

  factory SupportTicketAttachment.fromMap(Map<String, dynamic> data) {
    return SupportTicketAttachment(
      attachmentId: '${data['attachmentId'] ?? ''}'.trim(),
      storagePath: '${data['storagePath'] ?? ''}'.trim(),
      fileName: '${data['fileName'] ?? ''}'.trim(),
      contentType: '${data['contentType'] ?? ''}'.trim(),
      createdAt: _timestampToDate(data['createdAt']),
    );
  }

  final String attachmentId;
  final String storagePath;
  final String fileName;
  final String contentType;
  final DateTime? createdAt;
}

class SupportTicketMessage {
  const SupportTicketMessage({
    required this.id,
    required this.messageId,
    required this.senderId,
    required this.senderType,
    required this.message,
    required this.createdAt,
    required this.adminRole,
    required this.adminDisplayName,
  });

  factory SupportTicketMessage.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SupportTicketMessage(
      id: snapshot.id,
      messageId: '${data['messageId'] ?? snapshot.id}'.trim(),
      senderId: '${data['senderId'] ?? ''}'.trim(),
      senderType: SupportMessageSenderTypeX.parse(
        '${data['senderType'] ?? ''}',
      ),
      message: '${data['message'] ?? ''}'.trim(),
      createdAt: _timestampToDate(data['createdAt']),
      adminRole: '${data['adminRole'] ?? ''}'.trim(),
      adminDisplayName: '${data['adminDisplayName'] ?? ''}'.trim(),
    );
  }

  final String id;
  final String messageId;
  final String senderId;
  final SupportMessageSenderType senderType;
  final String message;
  final DateTime? createdAt;
  final String adminRole;
  final String adminDisplayName;
}
