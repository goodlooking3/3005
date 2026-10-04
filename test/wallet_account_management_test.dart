import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_model.dart';

void main() {
  late int cashAccountId;
  const walletId = 'wallet-multi-currency-test';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await LocalDatabase.instance.resetForTests();
    final db = await LocalDatabase.instance.database;
    cashAccountId = await db.insert('accounts', {
      'code': 'TEST-WALLET-CASH',
      'name': 'صندوق الاختبار',
      'type': 'نقدية',
      'kind': 'cash',
      'currency': 'SAR',
      'is_group': 0,
      'active': 1,
    });
    await db.insert('account_currencies', {
      'account_id': cashAccountId,
      'currency': 'SAR',
      'is_primary': 1,
    });
    await db.insert('account_currencies', {
      'account_id': cashAccountId,
      'currency': 'USD',
      'is_primary': 0,
    });
    await db.insert('wallets', {
      'id': walletId,
      'name': 'محفظة الاختبار',
      'provider_id': 'test-provider',
      'provider_name': 'مزود الاختبار',
    });
  });

  test('saves one linked wallet account for each permitted currency', () async {
    final repository = WalletRepositoryImpl();
    await repository.saveAccounts([
      WalletAccount(
        walletId: walletId,
        name: 'حساب الصندوق',
        currency: 'SAR',
        accountId: cashAccountId,
      ),
      WalletAccount(
        walletId: walletId,
        name: 'حساب الصندوق',
        currency: 'USD',
        accountId: cashAccountId,
      ),
    ]);

    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'wallet_accounts',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      orderBy: 'currency ASC',
    );
    expect(rows.map((row) => row['currency']).toList(), ['SAR', 'USD']);
    expect(rows.every((row) => row['account_id'] == cashAccountId), isTrue);
  });

  test('rejects a currency not permitted by the linked account atomically',
      () async {
    final repository = WalletRepositoryImpl();
    await expectLater(
      repository.saveAccounts([
        WalletAccount(
          walletId: walletId,
          name: 'حساب الصندوق',
          currency: 'SAR',
          accountId: cashAccountId,
        ),
        WalletAccount(
          walletId: walletId,
          name: 'حساب الصندوق',
          currency: 'EUR',
          accountId: cashAccountId,
        ),
      ]),
      throwsStateError,
    );

    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'wallet_accounts',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
    );
    expect(rows, isEmpty);
  });
}
