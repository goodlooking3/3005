import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/services/report_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await LocalDatabase.instance.resetForTests();
  });

  test('balance sheet reconciles and income reversals net correctly', () async {
    final db = await LocalDatabase.instance.database;
    await _seedProfiles(db);
    final ids = await _accounts(db);
    final customerId = await _party(db, ids['AR']!, 'customer', 'عميل تقارير');
    final supplierId = await _party(db, ids['AP']!, 'supplier', 'مورد تقارير');

    await _post(db, 'OPEN', DateTime.utc(2026, 1, 1), [
      _line(ids['CASH']!, 'الصندوق', debit: 1000),
      _line(ids['EQUITY']!, 'رأس المال', credit: 1000),
    ]);
    await _post(db, 'SALE', DateTime.utc(2026, 6, 1), [
      _line(ids['AR']!, 'الذمم المدينة', debit: 300, partyId: customerId),
      _line(ids['REV']!, 'الإيرادات', credit: 300),
    ]);
    await _post(db, 'RECEIPT', DateTime.utc(2026, 7, 15), [
      _line(ids['CASH']!, 'الصندوق', debit: 100),
      _line(ids['AR']!, 'الذمم المدينة', credit: 100, partyId: customerId),
    ]);
    await _post(db, 'BILL', DateTime.utc(2026, 9, 1), [
      _line(ids['EXP']!, 'المصروفات', debit: 200),
      _line(ids['AP']!, 'الذمم الدائنة', credit: 200, partyId: supplierId),
    ]);
    await _post(db, 'PAYMENT', DateTime.utc(2026, 10, 1), [
      _line(ids['AP']!, 'الذمم الدائنة', debit: 50, partyId: supplierId),
      _line(ids['CASH']!, 'الصندوق', credit: 50),
    ]);
    await _post(db, 'RETURN', DateTime.utc(2026, 10, 3), [
      _line(ids['REV']!, 'الإيرادات', debit: 20),
      _line(ids['CASH']!, 'الصندوق', credit: 20),
    ]);

    final service = ReportService();
    final asOf = DateTime.utc(2026, 10, 5);
    final profit = await service.profitAndLoss(
      currency: 'SAR',
      from: DateTime.utc(2026, 1, 1),
      to: asOf,
    );
    expect(profit.revenue, 280);
    expect(profit.expenses, 200);
    expect(profit.net, 80);

    final position = await service.balanceSheet(asOf: asOf);
    expect(position.currency, 'SAR');
    expect(position.assets, 1230);
    expect(position.liabilities, 150);
    expect(position.equity, 1000);
    expect(position.unclosedResult, 80);
    expect(position.difference, closeTo(0, 0.000001));
    expect(position.isBalanced, isTrue);
  });

  test('aging applies settlements FIFO per party and reports control residual',
      () async {
    final db = await LocalDatabase.instance.database;
    await _seedProfiles(db);
    final ids = await _accounts(db);
    final customerId = await _party(db, ids['AR']!, 'customer', 'عميل أعمار');
    final supplierId = await _party(db, ids['AP']!, 'supplier', 'مورد أعمار');
    await _post(db, 'INV-1', DateTime.utc(2026, 6, 1), [
      _line(ids['AR']!, 'الذمم المدينة', debit: 300, partyId: customerId),
      _line(ids['REV']!, 'الإيرادات', credit: 300),
    ]);
    await _post(db, 'RCPT-1', DateTime.utc(2026, 7, 15), [
      _line(ids['CASH']!, 'الصندوق', debit: 100),
      _line(ids['AR']!, 'الذمم المدينة', credit: 100, partyId: customerId),
    ]);
    await _post(db, 'BILL-1', DateTime.utc(2026, 9, 1), [
      _line(ids['EXP']!, 'المصروفات', debit: 200),
      _line(ids['AP']!, 'الذمم الدائنة', credit: 200, partyId: supplierId),
    ]);
    await _post(db, 'PAY-1', DateTime.utc(2026, 10, 1), [
      _line(ids['AP']!, 'الذمم الدائنة', debit: 50, partyId: supplierId),
      _line(ids['CASH']!, 'الصندوق', credit: 50),
    ]);
    await db.insert('journal_lines', {
      'journal_entry_id': (await db.query('journal_entries',
              where: 'number = ?', whereArgs: ['INV-1']))
          .single['id'],
      'account_id': ids['AR'],
      'account_name': 'الذمم المدينة',
      'debit': 40,
      'credit': 0,
      'currency': 'SAR',
      'base_debit': 40,
      'base_credit': 0,
    });

    final service = ReportService();
    final asOf = DateTime.utc(2026, 10, 5);
    final receivables = await service.receivablesAging(asOf: asOf);
    final customer =
        receivables.rows.singleWhere((row) => row.partyId == customerId);
    expect(customer.daysOver90, 200);
    expect(customer.openItems, 200);
    expect(receivables.unallocated.single.currency, 'SAR');
    expect(receivables.unallocated.single.balance, 40);

    final payables = await service.payablesAging(asOf: asOf);
    final supplier =
        payables.rows.singleWhere((row) => row.partyId == supplierId);
    expect(supplier.days31To60, 150);
    expect(supplier.openItems, 150);
    expect(payables.unallocated, isEmpty);

    final statement = await service.partyStatement(
      partyId: customerId,
      partyType: 'customer',
      currency: 'SAR',
    );
    expect(statement.map((line) => line.number), ['INV-1', 'RCPT-1']);
    expect(statement.map((line) => line.balance), [300, 200]);
  });

  test(
      'base-currency position refuses foreign opening balance without valuation',
      () async {
    final db = await LocalDatabase.instance.database;
    await _seedProfiles(db);
    await db.insert('accounts', {
      'code': 'USD-CASH',
      'name': 'صندوق أجنبي',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'USD',
      'opening_balance': 25.0,
    });

    await expectLater(
      ReportService().balanceSheet(asOf: DateTime.utc(2026, 10, 5)),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _seedProfiles(Database db) async {
  await db.insert(
    'user_profile',
    {'id': 1, 'display_name': 'اختبار', 'role': 'admin'},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  await db.insert(
    'company_profile',
    {'id': 1, 'name': 'منشأة اختبار', 'base_currency': 'SAR'},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, int>> _accounts(Database db) async {
  final result = <String, int>{};
  for (final row in [
    ('CASH', '1000', 'الصندوق', 'cash'),
    ('AR', '1200', 'الذمم المدينة', 'customer'),
    ('AP', '2100', 'الذمم الدائنة', 'supplier'),
    ('EQUITY', '3000', 'رأس المال', 'equity'),
    ('REV', '4000', 'الإيرادات', 'revenue'),
    ('EXP', '5000', 'المصروفات', 'expense'),
  ]) {
    result[row.$1] = await db.insert('accounts', {
      'code': row.$2,
      'name': row.$3,
      'type': row.$3,
      'kind': row.$4,
      'currency': 'SAR',
    });
  }
  return result;
}

Future<int> _party(Database db, int accountId, String type, String name) =>
    db.insert('parties', {
      'account_id': accountId,
      'name': name,
      'type': type,
      'currency': 'SAR',
    });

Map<String, Object?> _line(
  int accountId,
  String name, {
  double debit = 0,
  double credit = 0,
  int? partyId,
}) =>
    {
      'accountId': accountId,
      'name': name,
      'debit': debit,
      'credit': credit,
      'partyId': partyId,
    };

Future<void> _post(
  Database db,
  String number,
  DateTime date,
  List<Map<String, Object?>> lines,
) async {
  await db.transaction((txn) async {
    final debitTotal = lines.fold<double>(
      0,
      (sum, line) => sum + (line['debit']! as double),
    );
    final creditTotal = lines.fold<double>(
      0,
      (sum, line) => sum + (line['credit']! as double),
    );
    final voucherId = await txn.insert('vouchers', {
      'number': number,
      'type': 'journal',
      'description': number,
      'amount': debitTotal,
      'currency': 'SAR',
      'date': date.toIso8601String(),
    });
    final entryId = await txn.insert('journal_entries', {
      'voucher_id': voucherId,
      'entry_date': date.toIso8601String(),
      'number': number,
      'description': number,
      'debit_total': debitTotal,
      'credit_total': creditTotal,
      'base_debit_total': debitTotal,
      'base_credit_total': creditTotal,
      'base_currency': 'SAR',
      'exchange_rate': 1.0,
      'source': 'test',
    });
    for (final line in lines) {
      final amount = line['debit']! as double;
      final credit = line['credit']! as double;
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'account_id': line['accountId'],
        'party_id': line['partyId'],
        'account_name': line['name'],
        'debit': amount,
        'credit': credit,
        'currency': 'SAR',
        'base_debit': amount,
        'base_credit': credit,
        'party_name': line['partyId'] == null ? null : 'طرف اختبار',
      });
    }
  });
}
