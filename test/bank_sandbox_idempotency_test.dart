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
    directory = await Directory.systemTemp.createTemp('wasel_bank_idempotency_');
    LocalDatabase.instance.setDatabaseDirectoryForTests(directory.path);
    await LocalDatabase.instance.resetForTests();
  });
  tearDown(() async {
    await LocalDatabase.instance.resetForTests();
    await directory.delete(recursive: true);
  });

  test('reposting an already-created bank voucher does not duplicate it', () async {
    final repository = AccountingRepository();
    final bankId = await repository.upsertAccount(const Account(
      code: '1200', name: 'بنك الاختبار', type: 'أصل', kind: AccountKind.bank,
      balance: 0, currency: 'SAR', currencies: ['SAR'],
    ));
    await repository.upsertAccount(const Account(
      code: '4100', name: 'إيراد الاختبار', type: 'إيراد', kind: AccountKind.revenue,
      balance: 0, currency: 'SAR', currencies: ['SAR'],
    ));
    final connector = BankSandboxConnector(
      repository: repository,
      linkedAccountId: bankId,
    );
    expect(await connector.syncSandbox(), 2);
    expect(await connector.syncSandbox(), 0);
    expect(await connector.postImported(), 2);
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('bank_transactions', where: 'status = ?', whereArgs: ['posted']);
    expect(rows, hasLength(2));
    await db.update('bank_transactions', {'status': 'imported'}, where: 'id = ?', whereArgs: [rows.first['id']]);
    expect(await connector.postImported(), 1);
    expect(await db.query('vouchers'), hasLength(2));
  });
}
