import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/accounting_repository.dart';
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
        [
          (customerAccount, 'ذمم العملاء', 100.0, 0.0, partyId),
          (revenueAccount, 'الإيرادات', 0.0, 100.0, null),
        ],
      );
    }
    await _post(
      db,
      'FUTURE-DUE',
      asOf.subtract(const Duration(days: 2)),
      asOf.add(const Duration(days: 1)),
      [
        (customerAccount, 'ذمم العملاء', 100.0, 0.0, partyId),
        (revenueAccount, 'الإيرادات', 0.0, 100.0, null),
      ],
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

  test('reversing a settlement restores the original invoice aging',
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
    final cashAccount = await db.insert('accounts', {
      'code': '1100',
      'name': 'الصندوق',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'SAR',
    });
    final partyId = await db.insert('parties', {
      'account_id': customerAccount,
      'name': 'عميل عكس دفعة',
      'type': 'customer',
      'currency': 'SAR',
    });
    final dueDate = DateTime.utc(2026, 2, 1);
    await _post(
      db,
      'REVERSAL-INVOICE',
      dueDate,
      dueDate,
      [
        (customerAccount, 'ذمم العملاء', 300.0, 0.0, partyId),
        (revenueAccount, 'الإيرادات', 0.0, 300.0, null),
      ],
    );
    await _post(
      db,
      'REVERSAL-PAYMENT',
      DateTime.utc(2026, 5, 1),
      null,
      [
        (cashAccount, 'الصندوق', 100.0, 0.0, null),
        (customerAccount, 'ذمم العملاء', 0.0, 100.0, partyId),
      ],
    );
    final paymentEntryId = (await db.query('journal_entries',
            where: 'number = ?', whereArgs: ['REVERSAL-PAYMENT']))
        .single['id']! as int;
    final service = ReportService();
    final beforeReversal = await service.receivablesAging(
      asOf: DateTime.utc(2026, 5, 5),
    );
    expect(beforeReversal.rows.single.openItems, 200);
    expect(beforeReversal.rows.single.daysOver90, 200);

    await AccountingRepository().reverseJournalEntry(
      journalEntryId: paymentEntryId,
      reversalNumber: 'REVERSAL-OF-PAYMENT',
      reversalDate: DateTime.utc(2026, 5, 10),
      reason: 'اختبار عكس دفعة',
    );
    final historical = await service.receivablesAging(
      asOf: DateTime.utc(2026, 5, 5),
    );
    expect(historical.rows.single.openItems, 200);
    final afterReversal = await service.receivablesAging(
      asOf: DateTime.utc(2026, 5, 15),
    );
    expect(afterReversal.rows.single.openItems, 300);
    expect(afterReversal.rows.single.daysOver90, 300);
    expect(afterReversal.unallocated, isEmpty);
  });

  test('overpayment remains visible as unapplied party credit', () async {
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
    final cashAccount = await db.insert('accounts', {
      'code': '1100',
      'name': 'الصندوق',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'SAR',
    });
    final partyId = await db.insert('parties', {
      'account_id': customerAccount,
      'name': 'عميل دفعة زائدة',
      'type': 'customer',
      'currency': 'SAR',
    });
    final date = DateTime.utc(2026, 10, 5);
    await _post(db, 'OVERPAY-INVOICE', date.subtract(const Duration(days: 60)), date.subtract(const Duration(days: 60)), [
      (customerAccount, 'ذمم العملاء', 100.0, 0.0, partyId),
      (revenueAccount, 'الإيرادات', 0.0, 100.0, null),
    ]);
    await _post(db, 'OVERPAY-RECEIPT', date.subtract(const Duration(days: 5)), null, [
      (cashAccount, 'الصندوق', 150.0, 0.0, null),
      (customerAccount, 'ذمم العملاء', 0.0, 150.0, partyId),
    ]);

    final report = await ReportService().receivablesAging(asOf: date);
    expect(report.rows.single.openItems, 0);
    expect(report.rows.single.unappliedCredit, 50);
    expect(report.rows.single.netBalance, -50);
    expect(report.unallocated, isEmpty);
  });
}

Future<void> _post(
  Database db,
  String number,
  DateTime date,
  DateTime? dueDate,
  List<(int, String, double, double, int?)> lines,
) async {
  await db.transaction((txn) async {
    final debitTotal = lines.fold<double>(0, (sum, line) => sum + line.$3);
    final creditTotal = lines.fold<double>(0, (sum, line) => sum + line.$4);
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
      'due_date': dueDate?.toIso8601String(),
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
        'party_name': line.$5 == null ? null : 'عميل اختبار',
      });
    }
  });
}
