class JournalEntry {
  final int id;
  final int voucherId;
  final DateTime date;
  final DateTime? dueDate;
  final String number;
  final String description;
  final double debitTotal;
  final double creditTotal;
  final String source;
  final int? reversalOfId;

  const JournalEntry({
    required this.id,
    required this.voucherId,
    required this.date,
    this.dueDate,
    required this.number,
    required this.description,
    required this.debitTotal,
    required this.creditTotal,
    required this.source,
    this.reversalOfId,
  });

  bool get balanced => (debitTotal - creditTotal).abs() <= 0.000001;

  factory JournalEntry.fromMap(Map<String, Object?> row) => JournalEntry(
        id: row['id']! as int,
        voucherId: row['voucher_id']! as int,
        date: DateTime.parse(row['entry_date']! as String),
        dueDate: row['due_date'] == null
            ? null
            : DateTime.parse(row['due_date']! as String),
        number: row['number']! as String,
        description: row['description']! as String,
        debitTotal: ((row['base_debit_total'] ?? row['debit_total'])! as num)
            .toDouble(),
        creditTotal: ((row['base_credit_total'] ?? row['credit_total'])! as num)
            .toDouble(),
        source: row['source']! as String,
        reversalOfId: row['reversal_of_id'] as int?,
      );
}
