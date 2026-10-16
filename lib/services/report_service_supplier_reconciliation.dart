part of 'report_service.dart';

class SupplierReconciliationTotals {
  final double receipts;
  final double returns;
  final double payments;

  const SupplierReconciliationTotals({
    required this.receipts,
    required this.returns,
    required this.payments,
  });

  double get netSettlement => payments + returns;
}

class SupplierReconciliationLine {
  final DateTime date;
  final String reference;
  final String description;
  final String currency;
  final String kind;
  final double amount;
  final double difference;
  final bool matched;
  final int? journalEntryId;

  const SupplierReconciliationLine({
    required this.date,
    required this.reference,
    required this.description,
    required this.currency,
    required this.kind,
    required this.amount,
    required this.difference,
    required this.matched,
    required this.journalEntryId,
  });
}

class SupplierReconciliationReport {
  final int supplierId;
  final DateTime? from;
  final DateTime to;
  final double openingBalance;
  final double currentBalance;
  final SupplierReconciliationTotals totals;
  final List<SupplierReconciliationLine> lines;
  final List<SupplierReconciliationLine> differences;

  const SupplierReconciliationReport({
    required this.supplierId,
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.currentBalance,
    required this.totals,
    required this.lines,
    required this.differences,
  });

  double get expectedBalance =>
      openingBalance + totals.receipts - totals.returns - totals.payments;

  double get balanceDifference => currentBalance - expectedBalance;

  bool get reconciled =>
      balanceDifference.abs() <= 0.01 && differences.isEmpty;
}

extension ReportServiceSupplierReconciliation on ReportService {
  Future<SupplierReconciliationReport> supplierReconciliation({
    required int supplierId,
    DateTime? from,
    required DateTime to,
    String? currency,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    if (from != null && from.isAfter(to)) {
      throw ArgumentError('بداية كشف المورد لا يمكن أن تتجاوز نهايته');
    }
    final supplier = await db.rawQuery('''
      SELECT p.id, p.account_id
      FROM parties p
      WHERE p.id = ? AND lower(p.type) = 'supplier'
        AND p.account_id IS NOT NULL
      LIMIT 1
    ''', [supplierId]);
    if (supplier.isEmpty) throw StateError('المورد غير موجود أو بلا حساب محاسبي');

    final normalizedCurrency = currency?.trim().toUpperCase();
    final rows = await _supplierJournalRows(
      db,
      supplierId: supplierId,
      currency: normalizedCurrency,
      to: to,
    );
    final openingCutoff = from == null ? null : _reportStartOfDay(from);
    var opening = 0.0;
    var current = 0.0;
    for (final row in rows) {
      final signed = _supplierSigned(row);
      current += signed;
      final date = DateTime.parse(row['entry_date']! as String);
      if (openingCutoff != null && date.isBefore(openingCutoff)) opening += signed;
    }

    final purchaseRows = await _supplierPurchaseRows(
      db,
      supplierId: supplierId,
      currency: normalizedCurrency,
      from: from,
      to: to,
    );
    final lines = <SupplierReconciliationLine>[];
    final differences = <SupplierReconciliationLine>[];
    final linkedEntryIds = <int>{};
    var receipts = 0.0;
    for (final purchase in purchaseRows) {
      final journalId = purchase['journal_entry_id'] as int?;
      if (journalId != null) linkedEntryIds.add(journalId);
      final documentTotal = (purchase['total'] as num).toDouble();
      receipts += documentTotal;
      final journal = rows.cast<Map<String, Object?>>().where(
        (row) => row['journal_entry_id'] == journalId,
      );
      final ledgerTotal = journal.fold<double>(
        0,
        (sum, row) => sum + _supplierSigned(row),
      );
      final difference = ledgerTotal - documentTotal;
      final line = SupplierReconciliationLine(
        date: DateTime.parse(purchase['created_at']! as String),
        reference: purchase['number']! as String,
        description: 'استلام شراء',
        currency: purchase['currency']! as String,
        kind: 'receipt',
        amount: documentTotal,
        difference: difference,
        matched: journalId != null && difference.abs() <= 0.01,
        journalEntryId: journalId,
      );
      lines.add(line);
      if (!line.matched) differences.add(line);
    }

    var payments = 0.0;
    var returns = 0.0;
    for (final row in rows) {
      final id = row['journal_entry_id']! as int;
      final date = DateTime.parse(row['entry_date']! as String);
      if (linkedEntryIds.contains(id) ||
          (from != null && date.isBefore(_reportStartOfDay(from)))) {
        continue;
      }
      final signed = _supplierSigned(row);
      if (signed >= -0.000001) continue;
      final amount = -signed;
      final description = row['description']! as String;
      final isReturn = _isSupplierReturn(description, row['number']! as String);
      if (isReturn) {
        returns += amount;
      } else {
        payments += amount;
      }
      lines.add(SupplierReconciliationLine(
        date: date,
        reference: row['number']! as String,
        description: description,
        currency: row['currency']! as String,
        kind: isReturn ? 'return' : 'payment',
        amount: amount,
        difference: 0,
        matched: true,
        journalEntryId: id,
      ));
    }
    lines.sort((a, b) => a.date.compareTo(b.date));
    return SupplierReconciliationReport(
      supplierId: supplierId,
      from: from,
      to: to,
      openingBalance: opening,
      currentBalance: current,
      totals: SupplierReconciliationTotals(
        receipts: receipts,
        returns: returns,
        payments: payments,
      ),
      lines: List.unmodifiable(lines),
      differences: List.unmodifiable(differences),
    );
  }

  Future<List<Map<String, Object?>>> _supplierJournalRows(
    Database db, {
    required int supplierId,
    required String? currency,
    required DateTime to,
  }) async {
    final args = <Object?>[supplierId, _reportDayAfter(to).toIso8601String()];
    var extra = '';
    if (currency != null && currency.isNotEmpty) {
      extra = ' AND UPPER(jl.currency) = ?';
      args.add(currency);
    }
    return db.rawQuery('''
      SELECT je.id journal_entry_id, je.entry_date, je.number,
        je.description, UPPER(jl.currency) currency,
        SUM(jl.debit) debit, SUM(jl.credit) credit
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN parties p ON p.id = jl.party_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE p.id = ? AND lower(p.type) = 'supplier'
        AND a.kind = 'supplier' AND p.account_id = jl.account_id
        AND je.entry_date < ?$extra
      GROUP BY je.id, je.entry_date, je.number, je.description, UPPER(jl.currency)
      ORDER BY je.entry_date, je.id
    ''', args);
  }

  Future<List<Map<String, Object?>>> _supplierPurchaseRows(
    Database db, {
    required int supplierId,
    required String? currency,
    required DateTime? from,
    required DateTime to,
  }) async {
    final args = <Object?>[supplierId, _reportDayAfter(to).toIso8601String()];
    var extra = '';
    if (from != null) {
      extra += ' AND po.created_at >= ?';
      args.add(_reportStartOfDay(from).toIso8601String());
    }
    if (currency != null && currency.isNotEmpty) {
      extra += ' AND UPPER(po.currency) = ?';
      args.add(currency);
    }
    return db.rawQuery('''
      SELECT po.number, po.total, UPPER(po.currency) currency,
        po.created_at, po.journal_entry_id
      FROM purchase_orders po
      WHERE po.party_id = ? AND po.created_at < ?$extra
      ORDER BY po.created_at, po.id
    ''', args);
  }

  double _supplierSigned(Map<String, Object?> row) =>
      (row['credit'] as num).toDouble() - (row['debit'] as num).toDouble();

  bool _isSupplierReturn(String description, String reference) {
    final value = '$description $reference'.toLowerCase();
    return value.contains('return') ||
        value.contains('مرتجع') ||
        value.contains('إرجاع');
  }
}
