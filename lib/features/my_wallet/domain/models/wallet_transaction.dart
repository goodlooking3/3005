enum WalletTransactionType { transfer, receipt, purchase, billPayment, topUp }

const walletTransactionStatuses = {
  'draft', 'review', 'approved', 'sent', 'confirmed', 'failed', 'pending',
  'needs_reconciliation', 'posted',
};

class WalletTransaction {
  final int? id;
  final String status;
  final int? fromWalletAccountId;
  final int? toWalletAccountId;
  final String fromAccount;
  final String toAccount;
  final WalletTransactionType type;
  final double amount;
  final String currency;
  final double? baseAmount;
  final String? baseCurrency;
  final double? exchangeRate;
  final double? feeAmount;
  final String? feeCurrency;
  final String note;
  final DateTime date;
  final String? reference;
  final String? sourceReference;
  final String? rawPayload;
  final String? relatedModule;
  final String? relatedEntityId;
  final int? journalEntryId;

  const WalletTransaction({
    this.id,
    this.status = 'posted',
    this.fromWalletAccountId,
    this.toWalletAccountId,
    required this.fromAccount,
    required this.toAccount,
    required this.type,
    required this.amount,
    required this.currency,
    this.baseAmount,
    this.baseCurrency,
    this.exchangeRate,
    this.feeAmount,
    this.feeCurrency,
    this.note = '',
    required this.date,
    this.reference,
    this.sourceReference,
    this.rawPayload,
    this.relatedModule,
    this.relatedEntityId,
    this.journalEntryId,
  });

  factory WalletTransaction.fromMap(Map<String, Object?> row) => WalletTransaction(
        id: row['id'] as int?,
        status: row['status'] as String? ?? 'posted',
        fromWalletAccountId: row['from_wallet_account_id'] as int?,
        toWalletAccountId: row['to_wallet_account_id'] as int?,
        fromAccount: row['from_account']! as String,
        toAccount: row['to_account']! as String,
        type: WalletTransactionType.values.byName(row['type']! as String),
        amount: (row['amount']! as num).toDouble(),
        currency: row['currency']! as String,
        baseAmount: (row['base_amount'] as num?)?.toDouble(),
        baseCurrency: row['base_currency'] as String?,
        exchangeRate: (row['exchange_rate'] as num?)?.toDouble(),
        feeAmount: (row['fee_amount'] as num?)?.toDouble(),
        feeCurrency: row['fee_currency'] as String?,
        note: row['note'] as String? ?? '',
        date: DateTime.parse(row['date']! as String),
        reference: row['reference'] as String?,
        sourceReference: row['source_reference'] as String?,
        rawPayload: row['raw_payload'] as String?,
        relatedModule: row['related_module'] as String?,
        relatedEntityId: row['related_entity_id'] as String?,
        journalEntryId: row['journal_entry_id'] as int?,
      );

  WalletTransaction copyWith({
    int? fromWalletAccountId,
    int? toWalletAccountId,
    int? journalEntryId,
    double? baseAmount,
    String? baseCurrency,
    double? exchangeRate,
    double? feeAmount,
    String? feeCurrency,
    String? status,
    String? sourceReference,
    String? rawPayload,
  }) => WalletTransaction(
        id: id,
        status: status ?? this.status,
        fromWalletAccountId: fromWalletAccountId ?? this.fromWalletAccountId,
        toWalletAccountId: toWalletAccountId ?? this.toWalletAccountId,
        fromAccount: fromAccount,
        toAccount: toAccount,
        type: type,
        amount: amount,
        currency: currency,
        baseAmount: baseAmount ?? this.baseAmount,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        exchangeRate: exchangeRate ?? this.exchangeRate,
        feeAmount: feeAmount ?? this.feeAmount,
        feeCurrency: feeCurrency ?? this.feeCurrency,
        note: note,
        date: date,
        reference: reference,
        sourceReference: sourceReference ?? this.sourceReference,
        rawPayload: rawPayload ?? this.rawPayload,
        relatedModule: relatedModule,
        relatedEntityId: relatedEntityId,
        journalEntryId: journalEntryId ?? this.journalEntryId,
      );
}

class WalletTransactionFilter {
  final String? walletId;
  final WalletTransactionType? type;
  final String? currency;
  final String? status;
  final DateTime? from;
  final DateTime? to;
  final String query;

  const WalletTransactionFilter({
    this.walletId,
    this.type,
    this.currency,
    this.status,
    this.from,
    this.to,
    this.query = '',
  });
}
