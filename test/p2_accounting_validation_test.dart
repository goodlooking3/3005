import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  test('rejects a voucher with a missing account without partial rows', () async {
    final repository = AccountingRepository();
    final voucher = Voucher(
      number: 'P2-MISSING',
      type: VoucherType.journal,
      description: 'حساب مفقود',
      amount: 100,
      currency: 'SAR',
      date: DateTime(2026, 9, 22),
      lines: const [
        VoucherLine(accountId: 99999, accountName: 'غير موجود', debit: 100),
        VoucherLine(accountId: 99998, accountName: 'غير موجود', credit: 100),
      ],
    );

    await expectLater(repository.insertVoucher(voucher), throwsStateError);
    final db = await LocalDatabase.instance.database;
    expect(await db.query('vouchers'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
  });

  test('rejects a voucher posting to the same account twice', () async {
    final repository = AccountingRepository();
    final accountId = await repository.upsertAccount(
      const Account(
        code: 'P2-SAME',
        name: 'حساب واحد',
        type: 'أصل',
      ),
    );
    final voucher = Voucher(
      number: 'P2-SAME-ACCOUNT',
      type: VoucherType.journal,
      description: 'حساب مكرر',
      amount: 100,
      currency: 'SAR',
      date: DateTime(2026, 9, 22),
      lines: [
        VoucherLine(accountId: accountId, accountName: 'حساب واحد', debit: 100),
        VoucherLine(accountId: accountId, accountName: 'حساب واحد', credit: 100),
      ],
    );

    await expectLater(repository.insertVoucher(voucher), throwsStateError);
  });

  test('allows a balanced voucher with two active accounts', () async {
    final repository = AccountingRepository();
    final debitId = await repository.upsertAccount(
      const Account(code: 'P2-D', name: 'مدين', type: 'أصل'),
    );
    final creditId = await repository.upsertAccount(
      const Account(code: 'P2-C', name: 'دائن', type: 'إيراد'),
    );
    final voucher = Voucher(
      number: 'P2-VALID',
      type: VoucherType.journal,
      description: 'قيد صالح',
      amount: 100,
      currency: 'SAR',
      date: DateTime(2026, 9, 22),
      lines: [
        VoucherLine(accountId: debitId, accountName: 'مدين', debit: 100),
        VoucherLine(accountId: creditId, accountName: 'دائن', credit: 100),
      ],
    );

    final voucherId = await repository.insertVoucher(voucher);
    expect(voucherId, greaterThan(0));
  });
}
