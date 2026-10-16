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

  test('matches receipts and separates payments from returns', () async {
    final db = await LocalDatabase.instance.database;
    await _seedProfiles(db);
    final ids = await _accounts(db);
    final supplierId = await _party(db, ids['AP']!, 'supplier', 'مورد تسوية');
    await _post(db, 'PUR-1', DateTime.utc(2026, 2, 1), [
      _line(ids['EXP']!, 'المصروفات', debit: 250),
      _line(ids['AP']!, 'الذمم الدائنة', credit: 250, partyId: supplierId),
    ]);
    final receiptEntry = (await db.query(
      'journal_entries',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: ['PUR-1'],
    )).single['id'] as int;
    await db.insert('purchase_orders', {
      'number': 'PUR-1',
      'party_id': supplierId,
      'vendor_name': 'مورد تسوية',
      'wallet_name': 'الصندوق',
      'total': 250,
      'currency': 'SAR',
      'status': 'posted',
      'created_at': DateTime.utc(2026, 2, 1).toIso8601String(),
      'journal_entry_id': receiptEntry,
    });
    await _post(db, 'PAY-1', DateTime.utc(2026, 3, 1), [
      _line(ids['AP']!, 'الذمم الدائنة', debit: 80, partyId: supplierId),
      _line(ids['CASH']!, 'الصندوق', credit: 80),
    ]);
    await _post(db, 'RETURN-1', DateTime.utc(2026, 3, 2), [
      _line(ids['AP']!, 'الذمم الدائنة', debit: 20, partyId: supplierId),
      _line(ids['CASH']!, 'الصندوق', credit: 20),
    ]);

    final report = await ReportService().supplierReconciliation(
      supplierId: supplierId,
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 3, 31),
      currency: 'SAR',
    );
    expect(report.totals.receipts, 250);
    expect(report.totals.payments, 80);
    expect(report.totals.returns, 20);
    expect(report.currentBalance, 150);
    expect(report.balanceDifference, 0);
    expect(report.differences, isEmpty);
    expect(report.reconciled, isTrue);
  });
}

Future<void> _seedProfiles(Database db) async {
  await db.insert('user_profile', {
    'id': 1,
    'display_name': 'اختبار',
    'role': 'admin',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('company_profile', {
    'id': 1,
    'name': 'منشأة اختبار',
    'base_currency': 'SAR',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Map<String, int>> _accounts(Database db) async {
  final result = <String, int>{};
  for (final row in [
    ('CASH', '1000', 'الصندوق', 'cash'),
    ('AP', '2100', 'الذمم الدائنة', 'supplier'),
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

Map<String, Object?> _line(int accountId, String name,
        {double debit = 0, double credit = 0, int? partyId}) =>
    {
      'accountId': accountId,
      'name': name,
      'debit': debit,
      'credit': credit,
      'partyId': partyId,
    };

Future<void> _post(Database db, String number, DateTime date,
    List<Map<String, Object?>> lines) async {
  await db.transaction((txn) async {
    final total = lines.fold<double>(
        0, (sum, line) => sum + (line['debit']! as double));
    final voucherId = await txn.insert('vouchers', {
      'number': number,
      'type': 'journal',
      'description': number,
      'amount': total,
      'currency': 'SAR',
      'date': date.toIso8601String(),
    });
    final entryId = await txn.insert('journal_entries', {
      'voucher_id': voucherId,
      'entry_date': date.toIso8601String(),
      'number': number,
      'description': number,
      'debit_total': total,
      'credit_total': total,
      'base_debit_total': total,
      'base_credit_total': total,
      'base_currency': 'SAR',
      'exchange_rate': 1.0,
      'source': 'test',
    });
    for (final line in lines) {
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'account_id': line['accountId'],
        'party_id': line['partyId'],
        'account_name': line['name'],
        'debit': line['debit'],
        'credit': line['credit'],
        'currency': 'SAR',
      });
    }
  });
}
