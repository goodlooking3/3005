part of '../accounting_repository.dart';

extension AccountingRepositoryReversals on AccountingRepository {
  /// Posts an exact opposite entry on a new open date; the source stays immutable.
  Future<int> reverseJournalEntry({
    required int journalEntryId,
    required String reversalNumber,
    required DateTime reversalDate,
    required String reason,
  }) async {
    final number = reversalNumber.trim();
    final note = reason.trim();
    if (journalEntryId <= 0 ||
        number.isEmpty ||
        note.isEmpty ||
        note.length > 300) {
      throw ArgumentError('رقم العكس وسببه ومعرّف القيد مطلوبة');
    }
    return LocalDatabase.instance.write((db) async {
      return db.transaction((txn) async {
        await AccountingAuthorization.instance
            .require(txn, AccountingPermission.reverseVouchers);
        final entries = await txn.query(
          'journal_entries',
          where: 'id = ?',
          whereArgs: [journalEntryId],
          limit: 1,
        );
        if (entries.isEmpty) throw StateError('القيد الأصلي غير موجود');
        final original = entries.single;
        if (original['reversal_of_id'] != null) {
          throw StateError('لا يمكن إنشاء عكس لقيد عكسي');
        }
        final existingReversal = await txn.query(
          'journal_entries',
          columns: ['id'],
          where: 'reversal_of_id = ?',
          whereArgs: [journalEntryId],
          limit: 1,
        );
        if (existingReversal.isNotEmpty) {
          throw StateError('سبق عكس هذا القيد؛ لن يُنشأ عكس مكرر');
        }
        final sourceVoucherRows = await txn.query(
          'vouchers',
          where: 'id = ?',
          whereArgs: [original['voucher_id']],
          limit: 1,
        );
        if (sourceVoucherRows.isEmpty) {
          throw StateError('مستند القيد الأصلي غير موجود');
        }
        final sourceVoucher = sourceVoucherRows.single;
        final lines = await txn.query(
          'journal_lines',
          where: 'journal_entry_id = ?',
          whereArgs: [journalEntryId],
          orderBy: 'id ASC',
        );
        if (lines.isEmpty) throw StateError('القيد الأصلي بلا أسطر دفتر');

        final description = 'عكس ${original['number']}: $note';
        final voucherId = await txn.insert('vouchers', {
          'number': number,
          'type': VoucherType.journal.name,
          'description': description,
          'amount': sourceVoucher['amount'],
          'currency': sourceVoucher['currency'],
          'base_amount': sourceVoucher['base_amount'],
          'base_currency': sourceVoucher['base_currency'],
          'exchange_rate': sourceVoucher['exchange_rate'],
          'date': reversalDate.toIso8601String(),
          'recipient_name': sourceVoucher['payer_name'],
          'payer_name': sourceVoucher['recipient_name'],
          'debit_account_id': sourceVoucher['credit_account_id'],
          'credit_account_id': sourceVoucher['debit_account_id'],
        });
        final originalBaseDebit = original['base_debit_total'] as num?;
        final originalBaseCredit = original['base_credit_total'] as num?;
        final reversalEntryId = await txn.insert('journal_entries', {
          'voucher_id': voucherId,
          'entry_date': reversalDate.toIso8601String(),
          'number': number,
          'description': description,
          'debit_total': original['credit_total'],
          'credit_total': original['debit_total'],
          'base_debit_total': originalBaseCredit ?? original['credit_total'],
          'base_credit_total': originalBaseDebit ?? original['debit_total'],
          'base_currency': original['base_currency'],
          'exchange_rate': original['exchange_rate'],
          'source': 'reversal',
          'reversal_of_id': journalEntryId,
        });

        for (final line in lines) {
          final accountName = line['account_name']! as String;
          final debit = (line['debit']! as num).toDouble();
          final credit = (line['credit']! as num).toDouble();
          final baseDebit = line['base_debit'] as num?;
          final baseCredit = line['base_credit'] as num?;
          final reversedLine = <String, Object?>{
            'account_id': line['account_id'],
            'party_id': line['party_id'],
            'account_name': accountName,
            'debit': credit,
            'credit': debit,
            'currency': line['currency'],
            'base_debit': baseCredit,
            'base_credit': baseDebit,
            'party_name': line['party_name'],
          };
          await txn.insert('voucher_lines', {
            'voucher_id': voucherId,
            ...reversedLine,
          });
          await txn.insert('journal_lines', {
            'journal_entry_id': reversalEntryId,
            ...reversedLine,
          });
        }
        await AuditRepository.instance.recordOn(
          txn,
          action: 'reverse_journal_entry',
          entityType: 'journal_entry',
          entityId: '$reversalEntryId',
          details: 'reversal_of=$journalEntryId; reason=$note',
        );
        await txn.insert('sync_queue', {
          'entity': 'voucher',
          'entity_id': voucherId,
          'operation': 'upsert',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'idempotency_key': 'voucher-$voucherId',
          'remote_version': 0,
        });
        return reversalEntryId;
      });
    });
  }
}
