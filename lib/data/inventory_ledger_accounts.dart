import 'package:sqflite/sqflite.dart';

import '../core/accounting.dart';
import 'currency_policy.dart';

class InventoryLedgerAccounts {
  final Account inventoryAsset;
  final Account costOfGoodsSold;

  const InventoryLedgerAccounts({
    required this.inventoryAsset,
    required this.costOfGoodsSold,
  });
}

class InventoryLedgerAccountResolver {
  const InventoryLedgerAccountResolver();

  Future<InventoryLedgerAccounts> ensure(
    Transaction txn, {
    required String currency,
  }) async {
    final normalizedCurrency = currency.trim().toUpperCase();
    await currencyPolicy.requireActive(txn, normalizedCurrency);

    final assets = await _ensureAccount(
      txn,
      code: '1000',
      name: 'الأصول',
      type: 'أصل',
      kind: AccountKind.asset,
      currency: normalizedCurrency,
      isGroup: true,
    );
    final expenses = await _ensureAccount(
      txn,
      code: '5000',
      name: 'المصروفات',
      type: 'مصروف',
      kind: AccountKind.expense,
      currency: normalizedCurrency,
      isGroup: true,
    );
    final inventory = await _ensureAccount(
      txn,
      code: '1300',
      name: 'المخزون',
      type: 'أصل',
      kind: AccountKind.asset,
      currency: normalizedCurrency,
      parentId: assets.id,
    );
    final costOfGoods = await _ensureAccount(
      txn,
      code: '5200',
      name: 'تكلفة البضاعة المباعة',
      type: 'مصروف',
      kind: AccountKind.expense,
      currency: normalizedCurrency,
      parentId: expenses.id,
    );

    return InventoryLedgerAccounts(
      inventoryAsset: inventory,
      costOfGoodsSold: costOfGoods,
    );
  }

  Future<Account> _ensureAccount(
    Transaction txn, {
    required String code,
    required String name,
    required String type,
    required AccountKind kind,
    required String currency,
    int? parentId,
    bool isGroup = false,
  }) async {
    final existing = await txn.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    late final int accountId;
    late final String accountName;
    late final String accountType;
    late final int? accountParentId;
    if (existing.isNotEmpty) {
      final row = existing.single;
      final existingKind = AccountKind.values.firstWhere(
        (candidate) => candidate.name == row['kind'],
        orElse: () => AccountKind.asset,
      );
      final existingIsGroup = (row['is_group'] as int? ?? 0) == 1;
      final existingIsActive = (row['active'] as int? ?? 1) == 1;
      if (!existingIsActive) {
        throw StateError(
            'حساب المخزون $code غير نشط ولا يمكن ترحيل الحركة إليه');
      }
      if (existingKind != kind ||
          existingIsGroup != isGroup ||
          (!isGroup && row['name'] != name)) {
        throw StateError(
          'رمز الحساب $code مستخدم لحساب غير متوافق؛ يلزم تعيين دليل الحسابات قبل الترحيل',
        );
      }
      accountId = row['id']! as int;
      accountName = row['name']! as String;
      accountType = row['type']! as String;
      accountParentId = row['parent_id'] as int?;
    } else {
      accountId = await txn.insert('accounts', {
        'code': code,
        'name': name,
        'type': type,
        'kind': kind.name,
        'parent_id': parentId,
        'is_group': isGroup ? 1 : 0,
        'currency': currency,
        'opening_balance': 0,
        'active': 1,
      });
      accountName = name;
      accountType = type;
      accountParentId = parentId;
    }

    final supported = await txn.query(
      'account_currencies',
      columns: ['account_id'],
      where: 'account_id = ? AND currency = ?',
      whereArgs: [accountId, currency],
      limit: 1,
    );
    if (supported.isEmpty) {
      await txn.insert('account_currencies', {
        'account_id': accountId,
        'currency': currency,
        'is_primary': 0,
      });
    }

    return Account(
      id: accountId,
      code: code,
      name: accountName,
      type: accountType,
      kind: kind,
      parentId: accountParentId,
      isGroup: isGroup,
      currency: currency,
    );
  }
}
