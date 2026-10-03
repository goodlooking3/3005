import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/accounting/application/chart_account_catalog.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'wasel_account_seed_policy_',
    );
    LocalDatabase.instance.setDatabaseDirectoryForTests(
      databaseDirectory.path,
    );
    await LocalDatabase.instance.resetForTests();
  });

  tearDown(() async {
    await LocalDatabase.instance.resetForTests();
    await databaseDirectory.delete(recursive: true);
  });

  test('a new local database starts without demo accounts or balances',
      () async {
    final repository = AccountingRepository();

    expect(await repository.accounts(), isEmpty);
    final summary = await repository.summary();
    expect(summary.cashBalance, 0);
    expect(summary.bankBalance, 0);
    expect(summary.vouchersCount, 0);
  });

  test('financial summary includes posted cash and bank journal movement', () async {
    final repository = AccountingRepository();
    final db = await LocalDatabase.instance.database;
    final cashId = await db.insert('accounts', {
      'code': 'TEST-CASH', 'name': 'نقد الاختبار', 'type': 'أصل', 'kind': 'cash',
      'currency': 'SAR', 'opening_balance': 100, 'active': 1, 'is_group': 0,
    });
    final bankId = await db.insert('accounts', {
      'code': 'TEST-BANK', 'name': 'بنك الاختبار', 'type': 'أصل', 'kind': 'bank',
      'currency': 'SAR', 'opening_balance': 200, 'active': 1, 'is_group': 0,
    });
    final voucherId = await db.insert('vouchers', {
      'number': 'TEST-SUMMARY', 'type': 'journal', 'description': 'اختبار الملخص',
      'amount': 90, 'currency': 'SAR', 'date': DateTime.now().toIso8601String(),
    });
    final entryId = await db.insert('journal_entries', {
      'voucher_id': voucherId, 'entry_date': DateTime.now().toIso8601String(),
      'number': 'TEST-SUMMARY', 'description': 'اختبار الملخص',
      'debit_total': 50, 'credit_total': 40,
    });
    await db.insert('journal_lines', {
      'journal_entry_id': entryId, 'account_id': cashId, 'account_name': 'نقد الاختبار',
      'debit': 50, 'credit': 0, 'currency': 'SAR',
    });
    await db.insert('journal_lines', {
      'journal_entry_id': entryId, 'account_id': bankId, 'account_name': 'بنك الاختبار',
      'debit': 0, 'credit': 40, 'currency': 'SAR',
    });
    final summary = await repository.summary();
    expect(summary.cashBalance, 150);
    expect(summary.bankBalance, 160);
  });

  test('chart structure may load without adding demo leaf accounts', () async {
    final repository = AccountingRepository();

    final accounts = await ChartAccountCatalog(repository).ensureDefaults();

    expect(accounts, hasLength(4));
    expect(accounts.every((account) => account.isGroup), isTrue);
    expect(accounts.every((account) => account.balance == 0), isTrue);
  });

  test('demo account seeding requires explicit development opt-in', () async {
    final repository = AccountingRepository();

    await expectLater(
      repository.seedDemoAccountsForDevelopment(explicitlyEnabled: false),
      throwsA(isA<StateError>()),
    );
    expect(await repository.accounts(), isEmpty);
  });

  test('explicit development opt-in can seed demo accounts on an empty chart',
      () async {
    final repository = AccountingRepository();
    await ChartAccountCatalog(repository).ensureDefaults();

    await repository.seedDemoAccountsForDevelopment(
      explicitlyEnabled: true,
    );

    final accounts = await repository.accounts();
    final demo = accounts.where((account) => !account.isGroup).toList();
    expect(demo.map((account) => account.code).toList(), [
      '1100',
      '1200',
      '4100',
      '5100',
    ]);
    expect(demo.map((account) => account.balance).toList(), [
      248650,
      58200,
      12840,
      3650,
    ]);
  });
}
