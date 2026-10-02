import 'package:intl/intl.dart';

enum EntryType { receipt, expense }

class Remittance {
  final int? id;
  final DateTime createdAt;
  final String sender;
  final String phone;
  final double amount;
  final String currency;
  final String reference;
  final String message;
  final String source;
  final EntryType type;

  const Remittance({
    this.id,
    required this.createdAt,
    required this.sender,
    required this.phone,
    required this.amount,
    required this.currency,
    required this.reference,
    required this.message,
    required this.source,
    this.type = EntryType.receipt,
  });

  String get formattedAmount =>
      '${NumberFormat('#,##0.##').format(amount)} $currency';
  String get formattedDate =>
      DateFormat('dd MMM yyyy، HH:mm', 'ar').format(createdAt);

  Map<String, Object?> toMap() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'sender': sender,
        'phone': phone,
        'amount': amount,
        'currency': currency,
        'reference': reference,
        'message': message,
        'source': source,
        'type': type.name,
      };

  factory Remittance.fromMap(Map<String, Object?> map) => Remittance(
        id: map['id'] as int?,
        createdAt: DateTime.parse(map['created_at']! as String),
        sender: map['sender']! as String,
        phone: map['phone']! as String,
        amount: (map['amount']! as num).toDouble(),
        currency: map['currency']! as String,
        reference: map['reference']! as String,
        message: map['message']! as String,
        source: map['source']! as String,
        type: (map['type'] as String?) == 'expense'
            ? EntryType.expense
            : EntryType.receipt,
      );
}

class ParsedMessage {
  final double amount;
  final String currency;
  final String reference;
  const ParsedMessage({
    required this.amount,
    required this.currency,
    required this.reference,
  });
}

class MessageParser {
  static ParsedMessage parse(String text) {
    final amountMatch = RegExp(
      r'(?:(\$|USD|SAR)\s*)?(\d[\d,\.]*\.?\d*)\s*(ريال|ر\.س|دولار|\$|USD|SAR|ر\.ي)?',
      caseSensitive: false,
    ).firstMatch(text);
    final referenceMatch = RegExp(
      r'(?:حوالة|مرجع|سند|إشعار|رقم)\D{0,12}(\d{6,12})',
      caseSensitive: false,
    ).firstMatch(text);
    final rawAmount = amountMatch?.group(2)?.replaceAll(',', '') ?? '0';
    final amount = double.tryParse(rawAmount) ?? 0;
    final currency = amountMatch?.group(1) ?? amountMatch?.group(3) ?? 'SAR';
    final reference = referenceMatch?.group(1) ?? 'غير محدد';
    return ParsedMessage(
      amount: amount,
      currency: currency,
      reference: reference,
    );
  }
}
