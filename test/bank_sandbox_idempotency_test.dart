import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/connectors/application/bank_sandbox_connector.dart';

void main() {
  late Directory directory;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('wasel_bank_idempotency_');
    LocalDatabase.instance.setDatabaseDirectoryForTests(directory.path);
    await LocalDatabase.instance.resetForTests();
  });
  tearDown(() async {
    await LocalDatabase.instance.resetForTests();
    await directory.delete(recursive: true);
  });

  test('reposting an already-created bank voucher does not duplicate it',
      () async {
    final repository = AccountingRepository();
    final bankId = await repository.upsertAccount(const Account(
      code: '1200',
      name: 'بنك الاختبار',
      type: 'أصل',
      kind: AccountKind.bank,
      balance: 0,
      currency: 'SAR',
      currencies: ['SAR'],
    ));
    final revenueId = await repository.upsertAccount(const Account(
      code: '4100',
      name: 'إيراد الاختبار',
      type: 'إيراد',
      kind: AccountKind.revenue,
      balance: 0,
      currency: 'SAR',
      currencies: ['SAR'],
    ));
    final expenseId = await repository.upsertAccount(const Account(
      code: '5100',
      name: 'مصروف الاختبار',
      type: 'مصروف',
      kind: AccountKind.expense,
      balance: 0,
      currency: 'SAR',
      currencies: ['SAR'],
    ));
    final connector = BankSandboxConnector(
      repository: repository,
      linkedAccountId: bankId,
    );
    expect(await connector.syncSandbox(), 2);
    expect(await connector.syncSandbox(), 0);
    final db = await LocalDatabase.instance.database;
    final imported = await repository.bankSandboxTransactions();
    final selections = {
      for (final row in imported)
        row['id']! as int: row['direction'] == 'credit' ? revenueId : expenseId,
    };
    expect(await connector.postImported(counterAccountIds: selections), 2);
    final rows = await db
        .query('bank_transactions', where: 'status = ?', whereArgs: ['posted']);
    expect(rows, hasLength(2));
    for (final row in rows) {
      final lines = await db.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [row['posted_voucher_id']],
      );
      final selectedId = row['direction'] == 'credit' ? revenueId : expenseId;
      expect(
        lines.any((line) =>
            line['account_id'] == selectedId &&
            ((row['direction'] == 'credit' && (line['credit'] as num) > 0) ||
                (row['direction'] == 'debit' && (line['debit'] as num) > 0))),
        isTrue,
      );
      expect(
        lines.any((line) => line['account_id'] == bankId),
        isTrue,
      );
    }
    await db.update(
      'bank_transactions',
      {'status': 'imported'},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    expect(
      await connector.postImported(
        counterAccountIds: {
          rows.first['id']! as int: selections[rows.first['id']]!
        },
      ),
      1,
    );
    expect(await db.query('vouchers'), hasLength(2));
  });

  test('unmatched bank lines are not posted automatically', () async {
    final repository = AccountingRepository();
    final bankId = await repository.upsertAccount(const Account(
      code: '1200',
      name: 'بنك الاختبار',
      type: 'أصل',
      kind: AccountKind.bank,
      balance: 0,
      currency: 'SAR',
      currencies: ['SAR'],
    ));
    await repository.upsertAccount(const Account(
      code: '4100',
      name: 'إيراد الاختبار',
      type: 'إيراد',
      kind: AccountKind.revenue,
      balance: 0,
      currency: 'SAR',
      currencies: ['SAR'],
    ));
    final connector = BankSandboxConnector(
      repository: repository,
      linkedAccountId: bankId,
    );
    await connector.syncSandbox();

    await expectLater(
      connector.postImported(counterAccountIds: const {}),
      throwsStateError,
    );
    final db = await LocalDatabase.instance.database;
    expect(await db.query('vouchers'), isEmpty);
    expect(
      await db.query('bank_transactions',
          where: 'status = ?', whereArgs: ['imported']),
      hasLength(2),
    );
  });
}
