class JournalEntry {
  final int id;
  final int voucherId;
  final DateTime date;
  final String number;
  final String description;
  final double debitTotal;
  final double creditTotal;
  final String source;

  const JournalEntry({
    required this.id,
    required this.voucherId,
    required this.date,
    required this.number,
    required this.description,
    required this.debitTotal,
    required this.creditTotal,
    required this.source,
  });

  bool get balanced => debitTotal == creditTotal;

  factory JournalEntry.fromMap(Map<String, Object?> row) => JournalEntry(
        id: row['id']! as int,
        voucherId: row['voucher_id']! as int,
        date: DateTime.parse(row['entry_date']! as String),
        number: row['number']! as String,
        description: row['description']! as String,
        debitTotal: (row['debit_total']! as num).toDouble(),
        creditTotal: (row['credit_total']! as num).toDouble(),
        source: row['source']! as String,
      );
}
