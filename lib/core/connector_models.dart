class ConnectorSettings {
  final String provider;
  final String displayName;
  final bool enabled;
  final String? endpoint;
  final String? qrPayload;
  final int? linkedAccountId;
  const ConnectorSettings({
    required this.provider,
    required this.displayName,
    this.enabled = false,
    this.endpoint,
    this.qrPayload,
    this.linkedAccountId,
  });
}

class BankSandboxTransaction {
  final String externalId;
  final double amount;
  final String currency;
  final String direction;
  final DateTime bookedAt;
  final String description;
  const BankSandboxTransaction({
    required this.externalId,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.bookedAt,
    required this.description,
  });
}

class IncomingMessage {
  final int? id;
  final String provider;
  final String sender;
  final String? senderPhone;
  final String body;
  final DateTime receivedAt;
  final bool archived;
  final double? parsedAmount;
  final String? parsedCurrency;
  final String? reference;
  const IncomingMessage({
    this.id,
    required this.provider,
    required this.sender,
    this.senderPhone,
    required this.body,
    required this.receivedAt,
    this.archived = false,
    this.parsedAmount,
    this.parsedCurrency,
    this.reference,
  });
}
