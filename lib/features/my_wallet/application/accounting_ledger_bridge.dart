import 'package:sqflite/sqflite.dart';

import '../../../core/accounting.dart';
import '../../../data/local_database.dart';
import '../../../data/accounting_repository.dart';
import '../../../data/currency_policy.dart';
import '../domain/models/wallet_transaction.dart';

class AccountingLedgerBridge {
  final AccountingRepository accounting;
  const AccountingLedgerBridge(this.accounting);

  Future<WalletTransaction> post(WalletTransaction transaction) =>
      LocalDatabase.instance.write(
        (db) => db.transaction(
          (txn) => postInTransaction(txn, transaction),
        ),
      );

  Future<WalletTransaction> postInTransaction(
    Transaction txn,
    WalletTransaction transaction,
  ) async {
    if (transaction.amount <= 0 ||
        !transaction.amount.isFinite ||
        transaction.currency.trim().isEmpty) {
      throw ArgumentError('Wallet transaction amount must be positive');
    }
    final valuation = await currencyPolicy.value(
      db: txn,
      amount: transaction.amount,
      currency: transaction.currency,
      at: transaction.date,
    );
    final voucher = await _voucher(txn, transaction);
    final voucherId = await accounting.insertVoucherInTransaction(txn, voucher);
    final journalRows = await txn.query(
      'journal_entries',
      columns: ['id'],
      where: 'voucher_id = ?',
      whereArgs: [voucherId],
      limit: 1,
    );
    if (journalRows.isEmpty) {
      throw StateError('Journal entry was not created for voucher $voucherId');
    }
    return transaction.copyWith(
      journalEntryId: journalRows.single['id'] as int,
      baseAmount: valuation.baseAmount,
      baseCurrency: valuation.baseCurrency,
      exchangeRate: valuation.exchangeRate,
    );
  }

  Future<Voucher> _voucher(
    Transaction txn,
    WalletTransaction transaction,
  ) async {
    final accounts = await _ensureChart(txn, transaction);
    return Voucher(
      number: transaction.reference?.trim().isNotEmpty == true
          ? transaction.reference!
          : 'WALLET-${transaction.date.microsecondsSinceEpoch}',
      type: _voucherType(transaction.type),
      description: transaction.note.trim().isEmpty
          ? transaction.type.name
          : transaction.note.trim(),
      amount: transaction.amount,
      currency: transaction.currency,
      date: transaction.date,
      debitAccountId: accounts.debit.id,
      creditAccountId: accounts.credit.id,
      lines: [
        VoucherLine(
            accountId: accounts.debit.id,
            accountName: accounts.debit.name,
            debit: transaction.amount),
        VoucherLine(
            accountId: accounts.credit.id,
            accountName: accounts.credit.name,
            credit: transaction.amount),
      ],
    );
  }

  Future<_LedgerAccounts> _ensureChart(
    Transaction txn,
    WalletTransaction transaction,
  ) async {
    final currentAssets = await _ensure(txn,
        code: '1000',
        name: 'الأصول المتداولة',
        kind: AccountKind.asset,
        currency: transaction.currency,
        group: true);
    final cashEquivalents = await _ensure(txn,
        code: '1100',
        name: 'النقدية وما في حكمها',
        kind: AccountKind.cash,
        currency: transaction.currency,
        parentId: currentAssets.id,
        group: true);
    final walletRoot = await _ensure(txn,
        code: '1130',
        name: 'الحسابات والمحافظ المالية',
        kind: AccountKind.cash,
        currency: transaction.currency,
        parentId: cashEquivalents.id,
        group: true);
    final fallbackSource = await _ensure(txn,
        code: '1130-${_safeCode(transaction.fromAccount)}',
        name: transaction.fromAccount,
        kind: AccountKind.cash,
        currency: transaction.currency,
        parentId: walletRoot.id);
    final fallbackDestination = await _ensure(txn,
        code: '1130-${_safeCode(transaction.toAccount)}',
        name: transaction.toAccount,
        kind: AccountKind.cash,
        currency: transaction.currency,
        parentId: walletRoot.id);
    final clearing = await _ensure(txn,
        code: '2100',
        name: 'حساب التحويلات الوسيطة',
        kind: AccountKind.liability,
        currency: transaction.currency,
        group: true);
    final income = await _ensure(txn,
        code: '4100',
        name: 'حساب الإيرادات والمقبوضات',
        kind: AccountKind.revenue,
        currency: transaction.currency,
        group: true);
    final expenses = await _ensure(txn,
        code: '5100',
        name: 'حساب المشتريات والمصروفات',
        kind: AccountKind.expense,
        currency: transaction.currency,
        group: true);

    final source = await _linkedAccount(txn, transaction.fromAccount, transaction.currency, transaction.fromWalletAccountId) ?? fallbackSource;
    final destination = await _linkedAccount(txn, transaction.toAccount, transaction.currency, transaction.toWalletAccountId) ?? fallbackDestination;
    return switch (transaction.type) {
      WalletTransactionType.transfer =>
        _LedgerAccounts(
          destination.id == fallbackDestination.id ? clearing : destination,
          source,
        ),
      WalletTransactionType.receipt ||
      WalletTransactionType.topUp =>
        _LedgerAccounts(destination, income),
      WalletTransactionType.purchase ||
      WalletTransactionType.billPayment =>
        _LedgerAccounts(expenses, source),
    };
  }

  Future<Account?> _linkedAccount(
    Transaction txn,
    String name,
    String currency,
    int? walletAccountId,
  ) async {
    final rows = await txn.rawQuery('''
      SELECT a.* FROM wallet_accounts wa
      JOIN accounts a ON a.id = wa.account_id
      WHERE (? IS NOT NULL AND wa.id = ? OR ? IS NULL AND wa.name = ? AND wa.currency = ?)
        AND (? IS NULL OR wa.currency = ?) AND wa.active = 1 AND a.active = 1
      ORDER BY wa.id DESC LIMIT 1
    ''', [walletAccountId, walletAccountId, walletAccountId, name.trim(), currency.trim().toUpperCase(), walletAccountId, currency.trim().toUpperCase()]);
    if (rows.isEmpty) return null;
    final account = _accountFromRow(rows.single);
    await _allowCurrency(txn, account.id!, currency);
    return account;
  }

  Future<Account> _ensure(Transaction txn,
      {required String code,
      required String name,
      required AccountKind kind,
      required String currency,
      int? parentId,
      bool group = false}) async {
    final rows = await txn.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final account = _accountFromRow(rows.single);
      await _allowCurrency(txn, account.id!, currency);
      return account;
    }
    final account = Account(
        code: code,
        name: name,
        type: kind.name,
        kind: kind,
        parentId: parentId,
        isGroup: group,
        currency: currency,
        currencies: [currency]);
    final id = await txn.insert('accounts', {
      'code': account.code,
      'name': account.name,
      'type': account.type,
      'kind': account.kind.name,
      'parent_id': account.parentId,
      'is_group': account.isGroup ? 1 : 0,
      'currency': account.currency,
      'opening_balance': account.balance,
    });
    await _allowCurrency(txn, id, currency);
    return Account(
        id: id,
        code: code,
        name: name,
        type: kind.name,
        kind: kind,
        parentId: parentId,
        isGroup: group,
        currency: currency,
        currencies: [currency]);
  }

  Future<void> _allowCurrency(
    Transaction txn,
    int accountId,
    String rawCurrency,
  ) async {
    final currency = rawCurrency.trim().toUpperCase();
    if (currency.isEmpty) throw ArgumentError('عملة المحفظة مطلوبة');
    final rows = await txn.query(
      'account_currencies',
      columns: ['account_id'],
      where: 'account_id = ? AND currency = ?',
      whereArgs: [accountId, currency],
      limit: 1,
    );
    if (rows.isEmpty) {
      await txn.insert('account_currencies', {
        'account_id': accountId,
        'currency': currency,
        'is_primary': 0,
      });
    }
  }

  Account _accountFromRow(Map<String, Object?> row) => Account(
        id: row['id'] as int,
        code: row['code']! as String,
        name: row['name']! as String,
        type: row['type']! as String,
        kind: AccountKind.values.firstWhere(
          (kind) => kind.name == row['kind'],
          orElse: () => AccountKind.asset,
        ),
        parentId: row['parent_id'] as int?,
        isGroup: (row['is_group'] as int) == 1,
        currency: row['currency']! as String,
        balance: (row['opening_balance']! as num).toDouble(),
      );

  String _safeCode(String value) => value.codeUnits
      .fold<int>(0, (sum, unit) => (sum + unit) % 99999)
      .toString()
      .padLeft(5, '0');

  VoucherType _voucherType(WalletTransactionType type) => switch (type) {
        WalletTransactionType.receipt ||
        WalletTransactionType.topUp =>
          VoucherType.receipt,
        WalletTransactionType.purchase ||
        WalletTransactionType.billPayment =>
          VoucherType.payment,
        WalletTransactionType.transfer => VoucherType.journal,
      };
}

class _LedgerAccounts {
  final Account debit;
  final Account credit;
  const _LedgerAccounts(this.debit, this.credit);
}
