import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/audit_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/data/local_database_schema.dart';
import 'package:wasel/services/auth_service.dart';
import 'package:wasel/services/report_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async => LocalDatabase.instance.resetForTests());

  test('fresh schema is v29 with append-only ledger and FK integrity',
      () async {
    final db = await LocalDatabase.instance.database;
    final version = Sqflite.firstIntValue(
      await db.rawQuery('PRAGMA user_version'),
    );
    expect(version, 29);

    final auditColumns = await db.rawQuery('PRAGMA table_info(audit_log)');
    expect(
      auditColumns.map((column) => column['name']),
      containsAll([
        'actor_id',
        'session_id',
        'entity_type',
        'entity_id',
        'action',
        'result',
        'created_at',
      ]),
    );
    final foreignKeyIssues = await db.rawQuery('PRAGMA foreign_key_check');
    expect(foreignKeyIssues, isEmpty);

    await db.insert('accounts', {
      'code': 'AUDIT-1',
      'name': 'حساب تدقيق',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'SAR',
    });
    final event = (await db.query(
      'audit_log',
      where: 'entity_type = ? AND action = ?',
      whereArgs: ['accounts', 'db.insert'],
      orderBy: 'id DESC',
      limit: 1,
    ))
        .single;
    expect(event['actor_id'], 'local-owner');
    expect(event['entity_id'], isNotNull);
    expect(event['result'], 'success');
    expect(DateTime.tryParse(event['created_at']! as String), isNotNull);

    await expectLater(
      db.update('audit_log', {'details': 'tampered'}),
      throwsA(anything),
    );
    await expectLater(
      db.delete('audit_log'),
      throwsA(anything),
    );
  });

  test('audit records include an active local session and rollback atomically',
      () async {
    final db = await LocalDatabase.instance.database;
    final sessionId = await AuditRepository.instance.beginLocalOwnerSession();
    expect(sessionId, hasLength(64));

    await db.insert('inventory_items', {
      'name': 'عنصر سجل',
      'sku': 'AUDIT-ITEM',
      'cost_price': 1.0,
      'sale_price': 2.0,
      'quantity': 1.0,
      'low_stock_threshold': 0.0,
      'currency': 'SAR',
    });
    final event = (await db.query(
      'audit_log',
      where: 'entity_type = ? AND action = ?',
      whereArgs: ['inventory_items', 'db.insert'],
      orderBy: 'id DESC',
      limit: 1,
    ))
        .single;
    expect(event['actor_id'], 'local-owner');
    expect(event['session_id'], sessionId);
    expect(event['result'], 'success');

    await expectLater(
      db.transaction((txn) async {
        await txn.insert('inventory_items', {
          'name': 'تغيير متراجع',
          'sku': 'ROLLBACK-AUDIT',
          'cost_price': 1.0,
          'sale_price': 2.0,
          'quantity': 1.0,
          'low_stock_threshold': 0.0,
          'currency': 'SAR',
        });
        throw StateError('rollback fixture');
      }),
      throwsStateError,
    );
    expect(
      await db.query('inventory_items',
          where: 'sku = ?', whereArgs: ['ROLLBACK-AUDIT']),
      isEmpty,
    );
    expect(
      await db.query('audit_log', where: 'entity_id = ?', whereArgs: ['2']),
      isEmpty,
    );
    await AuditRepository.instance.endLocalOwnerSession();

    await expectLater(
      LocalDatabase.instance.write<void>((_) async {
        throw StateError('private input must not be logged');
      }),
      throwsStateError,
    );
    final failure = (await db.query(
      'audit_log',
      where: 'action = ? AND result = ?',
      whereArgs: ['db.write', 'failure'],
      orderBy: 'id DESC',
      limit: 1,
    ))
        .single;
    expect(failure['actor_id'], 'local-owner');
    expect(failure['session_id'], isNull);
    expect(failure['entity_type'], 'application');
    expect((failure['details'] as String), contains('StateError'));
    expect((failure['details'] as String), isNot(contains('private input')));
  });

  test('authentication audit captures outcomes and local session identity',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.createAccount(
        email: 'owner@example.test', password: 'secret123');
    expect(
      await auth.signIn(email: 'owner@example.test', password: 'secret123'),
      isTrue,
    );
    expect(
      await auth.signIn(email: 'owner@example.test', password: 'incorrect'),
      isFalse,
    );
    await auth.setRemembered(false, keepSession: true);

    var events = await AccountingRepository().audit();
    final signIns = events.where((event) => event.action == 'auth.sign_in');
    final successful =
        signIns.singleWhere((event) => event.result == 'success');
    final failed = signIns.singleWhere((event) => event.result == 'failure');
    expect(successful.actorId, 'local-owner');
    expect(successful.entityType, 'local_account');
    expect(successful.sessionId, isNotEmpty);
    expect(failed.actorId, 'local-owner');
    expect(failed.sessionId, successful.sessionId);
    expect(events.any((event) => event.details.contains('secret123')), isFalse);

    await auth.setRemembered(false);
    events = await AccountingRepository().audit();
    final signedOut =
        events.singleWhere((event) => event.action == 'auth.sign_out');
    expect(signedOut.actorId, 'local-owner');
    expect(signedOut.sessionId, successful.sessionId);
    final context = await (await LocalDatabase.instance.database)
        .query('audit_context', where: 'id = ?', whereArgs: [1]);
    expect(context.single['session_id'], isNull);
  });

  test('v27 migration preserves legacy rows and installs audited writes',
      () async {
    final directory = await Directory.systemTemp.createTemp('wasel-v27-');
    final db = await LocalDatabase.instance.openVersionedDatabaseForTests(
      directory: directory.path,
      version: 27,
      onCreate: (database, _) async {
        await database.execute('''
            CREATE TABLE audit_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at TEXT NOT NULL,
              action TEXT NOT NULL,
              details TEXT NOT NULL
            )
          ''');
        await database.execute('''
            CREATE TABLE accounts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL,
              name TEXT NOT NULL
            )
          ''');
        await database.execute(
          'CREATE TABLE vouchers (id INTEGER PRIMARY KEY, number TEXT NOT NULL)',
        );
        await database.execute('''
            CREATE TABLE journal_entries (
              id INTEGER PRIMARY KEY,
              voucher_id INTEGER NOT NULL,
              entry_date TEXT NOT NULL,
              number TEXT NOT NULL,
              debit_total REAL NOT NULL,
              credit_total REAL NOT NULL
            )
          ''');
        await database.execute(
          'CREATE TABLE journal_lines (id INTEGER PRIMARY KEY, journal_entry_id INTEGER NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE voucher_lines (id INTEGER PRIMARY KEY, voucher_id INTEGER NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE parties (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE company_profile (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
        );
        await database.execute('''
            CREATE TABLE user_profile (
              id INTEGER PRIMARY KEY,
              display_name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'admin'
            )
          ''');
        await database.insert('audit_log', {
          'created_at': '2026-10-01T12:00:00.000Z',
          'action': 'legacy_event',
          'details': 'preserve this row',
        });
      },
    );
    try {
      await LocalDatabaseSchema.upgrade(db, 27);
      await db.execute('PRAGMA user_version = 29');
      final legacy = (await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['legacy_event'],
      ))
          .single;
      expect(legacy['action'], 'legacy_event');
      expect(legacy['details'], 'preserve this row');
      expect(legacy['actor_id'], 'legacy/unknown');
      expect(legacy['entity_type'], 'legacy/unknown');
      expect(legacy['result'], 'legacy/unknown');
      expect(
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')),
        29,
      );

      await db.insert('accounts', {'code': 'AFTER-MIGRATION', 'name': 'تجربة'});
      final migratedEvent = (await db.query(
        'audit_log',
        where: 'entity_type = ? AND action = ?',
        whereArgs: ['accounts', 'db.insert'],
        limit: 1,
      ))
          .single;
      expect(migratedEvent['actor_id'], 'local-owner');
      expect(migratedEvent['result'], 'success');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });

  test('reports and summary use journal lines, not voucher-line mirrors',
      () async {
    final db = await LocalDatabase.instance.database;
    await db.insert('accounts', {
      'id': 101,
      'code': 'TEST-CASH',
      'name': 'الصندوق',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'SAR',
    });
    await db.insert('accounts', {
      'id': 401,
      'code': 'TEST-SALES',
      'name': 'المبيعات',
      'type': 'إيراد',
      'kind': 'revenue',
      'currency': 'SAR',
    });
    final repository = AccountingRepository();
    final voucherId = await repository.insertVoucher(
      Voucher(
        number: 'PHASE1-SOT-1',
        type: VoucherType.journal,
        description: 'قيد اختبار مصدر الحقيقة',
        amount: 100,
        currency: 'SAR',
        date: DateTime.utc(2026, 10, 5),
        lines: const [
          VoucherLine(accountId: 101, accountName: 'الصندوق', debit: 100),
          VoucherLine(accountId: 401, accountName: 'المبيعات', credit: 100),
        ],
      ),
    );
    await db.update(
      'voucher_lines',
      {'debit': 999.0, 'credit': 0.0},
      where: 'voucher_id = ? AND debit > 0',
      whereArgs: [voucherId],
    );

    final ledger = await ReportService().generalLedger(
      currency: 'SAR',
      from: DateTime.utc(2026, 10, 5),
      to: DateTime.utc(2026, 10, 5, 23, 59, 59),
    );
    expect(ledger.map((row) => row.debit), contains(100.0));
    expect(ledger.map((row) => row.debit), isNot(contains(999.0)));

    final trialBalance = await ReportService().trialBalance(currency: 'SAR');
    expect(
        trialBalance.singleWhere((row) => row.code == 'TEST-CASH').debit, 100);
    expect(trialBalance.singleWhere((row) => row.code == 'TEST-SALES').credit,
        100);
    final profitLoss = await ReportService().profitAndLoss(currency: 'SAR');
    expect(profitLoss.revenue, 100);
    final summary = await repository.summary();
    expect(summary.totalDebits, 100);
    expect(summary.totalCredits, 100);
  });
}
