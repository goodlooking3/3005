import 'package:sqflite/sqflite.dart';

import '../core/accounting.dart';
import 'accounting_repository.dart';
import 'inventory_ledger_accounts.dart';

class InventoryLedgerPosting {
  final AccountingRepository accounting;
  final InventoryLedgerAccountResolver accountResolver;

  const InventoryLedgerPosting(
    this.accounting, {
    this.accountResolver = const InventoryLedgerAccountResolver(),
  });

  Future<int?> postCostOfGoods({
    required Transaction txn,
    required String number,
    required String description,
    required double amount,
    required String currency,
    required DateTime date,
    bool reverse = false,
  }) async {
    if (!amount.isFinite || amount < 0) {
      throw ArgumentError('تكلفة البضاعة غير صالحة');
    }
    if (amount == 0) return null;

    final accounts = await accountResolver.ensure(txn, currency: currency);
    final debitAccount =
        reverse ? accounts.inventoryAsset : accounts.costOfGoodsSold;
    final creditAccount =
        reverse ? accounts.costOfGoodsSold : accounts.inventoryAsset;
    final voucherId = await accounting.insertVoucherInTransaction(
      txn,
      Voucher(
        number: number,
        type: VoucherType.journal,
        description: description,
        amount: amount,
        currency: currency,
        date: date,
        debitAccountId: debitAccount.id,
        creditAccountId: creditAccount.id,
        lines: [
          VoucherLine(
            accountId: debitAccount.id,
            accountName: debitAccount.name,
            debit: amount,
          ),
          VoucherLine(
            accountId: creditAccount.id,
            accountName: creditAccount.name,
            credit: amount,
          ),
        ],
      ),
    );
    final journalRows = await txn.query(
      'journal_entries',
      columns: ['id'],
      where: 'voucher_id = ?',
      whereArgs: [voucherId],
      limit: 1,
    );
    if (journalRows.isEmpty) {
      throw StateError('لم يُنشأ قيد تكلفة البضاعة للسند $voucherId');
    }
    return journalRows.single['id'] as int;
  }
}
