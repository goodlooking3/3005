import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_purchases/data/datasources/local_vendors_db.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';
import 'package:wasel/features/my_sales/data/datasources/inventory_local_db.dart';
import 'package:wasel/features/my_sales/domain/inventory_item.dart';
import 'package:wasel/features/my_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_model.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_transaction.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  test('wallet batch import rolls back every financial row on failure',
      () async {
    final repository = WalletRepositoryImpl();
    await expectLater(
      repository.importTransactions([
        WalletTransaction(
          fromAccount: 'صندوق الدفعة',
          toAccount: 'مورد الدفعة',
          type: WalletTransactionType.purchase,
          amount: 25,
          currency: 'SAR',
          date: DateTime(2026, 9, 1),
          sourceReference: 'BATCH-ATOMIC-1',
        ),
        WalletTransaction(
          fromAccount: 'صندوق الدفعة',
          toAccount: 'مورد الدفعة',
          type: WalletTransactionType.purchase,
          amount: 0,
          currency: 'SAR',
          date: DateTime(2026, 9, 1),
          sourceReference: 'BATCH-ATOMIC-2',
        ),
      ]),
      throwsArgumentError,
    );

    final db = await LocalDatabase.instance.database;
    expect(await db.query('wallet_transactions'), isEmpty);
    expect(await db.query('vouchers'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('journal_lines'), isEmpty);
    expect(await db.query('accounts'), isEmpty);
  });

  test('wallet transaction preserves selected account IDs with duplicate names',
      () async {
    final db = await LocalDatabase.instance.database;
    await db.insert('wallets', {
      'id': 'wallet-a',
      'name': 'محفظة أ',
      'provider_id': 'test',
      'provider_name': 'اختبار',
    });
    await db.insert('wallets', {
      'id': 'wallet-b',
      'name': 'محفظة ب',
      'provider_id': 'test',
      'provider_name': 'اختبار',
    });
    final firstAccount = await db.insert('accounts', {
      'code': 'TEST-WALLET-A',
      'name': 'صندوق أ',
      'type': 'نقدية',
      'kind': 'cash',
      'currency': 'SAR',
      'is_group': 0,
      'active': 1,
    });
    final secondAccount = await db.insert('accounts', {
      'code': 'TEST-WALLET-B',
      'name': 'صندوق ب',
      'type': 'نقدية',
      'kind': 'cash',
      'currency': 'SAR',
      'is_group': 0,
      'active': 1,
    });
    final firstWalletAccount = await db.insert('wallet_accounts', {
      'wallet_id': 'wallet-a',
      'name': 'حساب مكرر الاسم',
      'currency': 'SAR',
      'account_id': firstAccount,
    });
    final secondWalletAccount = await db.insert('wallet_accounts', {
      'wallet_id': 'wallet-b',
      'name': 'حساب مكرر الاسم',
      'currency': 'SAR',
      'account_id': secondAccount,
    });

    await WalletRepositoryImpl().saveTransaction(WalletTransaction(
      fromAccount: 'حساب مكرر الاسم',
      toAccount: 'حساب مكرر الاسم',
      fromWalletAccountId: firstWalletAccount,
      toWalletAccountId: secondWalletAccount,
      type: WalletTransactionType.transfer,
      amount: 7,
      currency: 'SAR',
      date: DateTime(2026, 9, 2),
      sourceReference: 'WALLET-ID-ATOMIC-1',
    ));

    final stored = (await db.query('wallet_transactions')).single;
    expect(stored['from_wallet_account_id'], firstWalletAccount);
    expect(stored['to_wallet_account_id'], secondWalletAccount);
    final journalId = stored['journal_entry_id'];
    final debit = (await db.query(
      'journal_lines',
      where: 'journal_entry_id = ? AND debit > 0',
      whereArgs: [journalId],
    ))
        .single;
    final credit = (await db.query(
      'journal_lines',
      where: 'journal_entry_id = ? AND credit > 0',
      whereArgs: [journalId],
    ))
        .single;
    expect(debit['account_id'], secondAccount);
    expect(credit['account_id'], firstAccount);
  });

  test('saving an existing inventory item updates its stable ID', () async {
    final repository = InventoryLocalDb();
    final id = await repository.save(const InventoryItem(
      name: 'صنف ثابت',
      sku: 'STABLE-001',
      costPrice: 5,
      salePrice: 8,
      quantity: 2,
    ));
    final returnedId = await repository.save(InventoryItem(
      id: id,
      name: 'صنف محدّث',
      sku: 'STABLE-001',
      costPrice: 6,
      salePrice: 9,
      quantity: 4,
    ));
    final db = await LocalDatabase.instance.database;
    final rows =
        await db.query('inventory_items', where: 'id = ?', whereArgs: [id]);
    expect(returnedId, id);
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'صنف محدّث');
    expect(rows.single['quantity'], 4.0);
  });

  test('updating a wallet preserves its linked account rows', () async {
    final db = await LocalDatabase.instance.database;
    await db.insert('wallets', {
      'id': 'wallet-preserve',
      'name': 'قبل التحديث',
      'provider_id': 'test',
      'provider_name': 'اختبار',
    });
    await db.insert('wallet_accounts', {
      'wallet_id': 'wallet-preserve',
      'name': 'حساب قائم',
      'currency': 'SAR',
      'account_id': 1,
    });

    await WalletRepositoryImpl().saveWallet(const Wallet(
      id: 'wallet-preserve',
      name: 'بعد التحديث',
      provider: WalletProviderConfig(id: 'test', name: 'اختبار'),
    ));

    final wallet = (await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: ['wallet-preserve'],
    ))
        .single;
    final accounts = await db.query(
      'wallet_accounts',
      where: 'wallet_id = ?',
      whereArgs: ['wallet-preserve'],
    );
    expect(wallet['name'], 'بعد التحديث');
    expect(accounts, hasLength(1));
    expect(accounts.single['name'], 'حساب قائم');
  });

  test('marketplace vendor links only to an active supplier and is audited',
      () async {
    final db = await LocalDatabase.instance.database;
    final partyId = await db.insert('parties', {
      'name': 'مورد السجل',
      'type': 'supplier',
      'active': 1,
    });
    final vendors = LocalVendorsDb();
    final vendorId = await vendors.saveVendor(
      const Vendor(name: 'متجر الاختبار', category: 'تجزئة'),
    );

    await expectLater(
      vendors.linkVendorToParty(vendorId: vendorId, partyId: partyId + 100),
      throwsStateError,
    );
    expect(
      (await db.query('marketplace_vendors',
              where: 'id = ?', whereArgs: [vendorId]))
          .single['party_id'],
      isNull,
    );
    await vendors.linkVendorToParty(vendorId: vendorId, partyId: partyId);
    expect(
      (await db.query('marketplace_vendors',
              where: 'id = ?', whereArgs: [vendorId]))
          .single['party_id'],
      partyId,
    );
    final audit = await db.query(
      'audit_log',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['marketplace_vendors', '$vendorId'],
    );
    expect(audit, isNotEmpty);
    expect(audit.last['result'], 'success');
  });
}
