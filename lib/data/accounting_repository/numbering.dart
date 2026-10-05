part of '../accounting_repository.dart';

extension AccountingRepositoryNumbering on AccountingRepository {
  /// Reserves a unique per-year voucher number; unused reservations may leave gaps.
  Future<String> nextVoucherNumber(
    VoucherType type, {
    DateTime? date,
  }) async {
    final when = date ?? DateTime.now();
    final prefix = switch (type) {
      VoucherType.receipt => 'RC',
      VoucherType.payment => 'PM',
      VoucherType.journal => 'JV',
    };
    final periodKey = '${when.year}';
    final base = '$prefix-$periodKey-';

    return LocalDatabase.instance.write((db) async {
      return db.transaction((txn) async {
        await AccountingAuthorization.instance
            .require(txn, AccountingPermission.postVouchers);
        final sequenceRows = await txn.query(
          'document_sequences',
          columns: ['current_value'],
          where: 'prefix = ? AND period_key = ?',
          whereArgs: [prefix, periodKey],
          limit: 1,
        );
        final sequenceValue = sequenceRows.isEmpty
            ? 0
            : sequenceRows.single['current_value'] as int;
        final numberRows = await txn.rawQuery(
          '''
          SELECT COALESCE(MAX(CAST(substr(number, ?) AS INTEGER)), 0) AS max_value
          FROM vouchers WHERE number LIKE ? COLLATE NOCASE
          ''',
          [base.length + 1, '$base%'],
        );
        final usedValue = (numberRows.single['max_value'] as num).toInt();
        final nextValue =
            (sequenceValue > usedValue ? sequenceValue : usedValue) + 1;
        await txn.insert(
          'document_sequences',
          {
            'prefix': prefix,
            'period_key': periodKey,
            'current_value': nextValue,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return '$base${nextValue.toString().padLeft(6, '0')}';
      });
    });
  }
}
