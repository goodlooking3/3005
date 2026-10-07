import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/services/report_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async => LocalDatabase.instance.resetForTests());

  test('aging bands include exact 0/30/31/60/61/90/91-day boundaries',
      () async {
    final db = await LocalDatabase.instance.database;
    await db.insert('user_profile', {
      'id': 1,
      'display_name': 'اختبار',
      'role': 'admin',
    });
    await db.insert('company_profile', {
      'id': 1,
      'name': 'منشأة اختبار',
      'base_currency': 'SAR',
    });
    final customerAccount = await db.insert('accounts', {
      'code': '1200',
      'name': 'ذمم العملاء',
      'type': 'أصل',
      'kind': 'customer',
      'currency': 'SAR',
    });
    final revenueAccount = await db.insert('accounts', {
      'code': '4000',
      'name': 'الإيرادات',
      'type': 'إيراد',
      'kind': 'revenue',
      'currency': 'SAR',
    });
    final partyId = await db.insert('parties', {
      'account_id': customerAccount,
      'name': 'عميل الحدود',
      'type': 'customer',
      'currency': 'SAR',
    });

    final asOf = DateTime.utc(2026, 10, 5);
    final ages = [0, 30, 31, 60, 61, 90, 91];
    for (var index = 0; index < ages.length; index++) {
      final dueDate = asOf.subtract(Duration(days: ages[index]));
      await _post(
        db,
        'BOUNDARY-$index',
        dueDate.subtract(const Duration(days: 10)),
        dueDate,
        customerAccount,
        revenueAccount,
        partyId,
      );
    }
    await _post(
      db,
      'FUTURE-DUE',
      asOf.subtract(const Duration(days: 2)),
      asOf.add(const Duration(days: 1)),
      customerAccount,
      revenueAccount,
      partyId,
    );

    final report = await ReportService().receivablesAging(asOf: asOf);
    final customer = report.rows.single;
    expect(customer.unaged, 0);
    expect(customer.notDue, 100);
    expect(customer.days0To30, 200);
    expect(customer.days31To60, 200);
    expect(customer.days61To90, 200);
    expect(customer.daysOver90, 100);
    expect(customer.openItems, 800);
    expect(report.unallocated, isEmpty);
  });
}

Future<void> _post(
  Database db,
  String number,
  DateTime date,
  DateTime dueDate,
  int receivablesAccountId,
  int revenueAccountId,
  int partyId,
) async {
  await db.transaction((txn) async {
    final voucherId = await txn.insert('vouchers', {
      'number': number,
      'type': 'journal',
      'description': number,
      'amount': 100.0,
      'currency': 'SAR',
      'date': date.toIso8601String(),
    });
    final entryId = await txn.insert('journal_entries', {
      'voucher_id': voucherId,
      'entry_date': date.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'number': number,
      'description': number,
      'debit_total': 100.0,
      'credit_total': 100.0,
      'base_debit_total': 100.0,
      'base_credit_total': 100.0,
      'base_currency': 'SAR',
      'exchange_rate': 1.0,
      'source': 'test',
    });
    for (final line in [
      (receivablesAccountId, 'ذمم العملاء', 100.0, 0.0, partyId),
      (revenueAccountId, 'الإيرادات', 0.0, 100.0, null),
    ]) {
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'account_id': line.$1,
        'party_id': line.$5,
        'account_name': line.$2,
        'debit': line.$3,
        'credit': line.$4,
        'currency': 'SAR',
        'base_debit': line.$3,
        'base_credit': line.$4,
        'party_name': line.$5 == null ? null : 'عميل الحدود',
      });
    }
  });
}
