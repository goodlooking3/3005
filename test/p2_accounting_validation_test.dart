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

  test('rejects a voucher with a missing account without partial rows',
      () async {
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
        VoucherLine(
            accountId: accountId, accountName: 'حساب واحد', credit: 100),
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

  test('rejects posting to a group account', () async {
    final repository = AccountingRepository();
    final groupId = await repository.upsertAccount(
      const Account(
        code: 'P2-GROUP',
        name: 'حساب تجميعي',
        type: 'أصل',
        isGroup: true,
      ),
    );
    final leafId = await repository.upsertAccount(
      const Account(code: 'P2-LEAF', name: 'حساب تفصيلي', type: 'أصل'),
    );
    final voucher = Voucher(
      number: 'P2-GROUP-VOUCHER',
      type: VoucherType.journal,
      description: 'منع الحساب التجميعي',
      amount: 10,
      currency: 'SAR',
      date: DateTime(2026, 9, 22),
      lines: [
        VoucherLine(accountId: groupId, accountName: 'حساب تجميعي', debit: 10),
        VoucherLine(accountId: leafId, accountName: 'حساب تفصيلي', credit: 10),
      ],
    );

    await expectLater(repository.insertVoucher(voucher), throwsStateError);
  });

  test('rejects inactive accounts without leaving voucher or ledger rows',
      () async {
    final repository = AccountingRepository();
    final inactiveId = await repository.upsertAccount(
      const Account(
        code: 'P2-INACTIVE',
        name: 'حساب متوقف',
        type: 'أصل',
        active: false,
      ),
    );
    final creditId = await repository.upsertAccount(
      const Account(code: 'P2-INACTIVE-C', name: 'دائن نشط', type: 'إيراد'),
    );
    final voucher = Voucher(
      number: 'P2-INACTIVE-ENTRY',
      type: VoucherType.journal,
      description: 'منع الحساب المتوقف',
      amount: 12,
      currency: 'SAR',
      date: DateTime(2026, 9, 22),
      lines: [
        VoucherLine(
            accountId: inactiveId, accountName: 'حساب متوقف', debit: 12),
        VoucherLine(accountId: creditId, accountName: 'دائن نشط', credit: 12),
      ],
    );

    await expectLater(repository.insertVoucher(voucher), throwsStateError);
    final db = await LocalDatabase.instance.database;
    expect(await db.query('vouchers'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
  });

  test('rejects duplicate voucher numbers atomically', () async {
    final repository = AccountingRepository();
    final debitId = await repository.upsertAccount(
      const Account(code: 'P2-DUP-D', name: 'مدين مكرر', type: 'أصل'),
    );
    final creditId = await repository.upsertAccount(
      const Account(code: 'P2-DUP-C', name: 'دائن مكرر', type: 'إيراد'),
    );
    Voucher build() => Voucher(
          number: 'P2-DUPLICATE',
          type: VoucherType.journal,
          description: 'رقم مكرر',
          amount: 20,
          currency: 'SAR',
          date: DateTime(2026, 9, 22),
          lines: [
            VoucherLine(
                accountId: debitId, accountName: 'مدين مكرر', debit: 20),
            VoucherLine(
                accountId: creditId, accountName: 'دائن مكرر', credit: 20),
          ],
        );

    await repository.insertVoucher(build());
    await expectLater(repository.insertVoucher(build()), throwsStateError);
    final db = await LocalDatabase.instance.database;
    expect(
        await db.query('vouchers',
            where: 'number = ?', whereArgs: ['P2-DUPLICATE']),
        hasLength(1));
  });

  test('rejects an account cycle across multiple parents', () async {
    final repository = AccountingRepository();
    final rootId = await repository.upsertAccount(
      const Account(code: 'P2-CYCLE-A', name: 'جذر دورة', type: 'أصل'),
    );
    final childId = await repository.upsertAccount(
      Account(
          code: 'P2-CYCLE-B', name: 'ابن دورة', type: 'أصل', parentId: rootId),
    );

    await expectLater(
      repository.upsertAccount(
        Account(
          id: rootId,
          code: 'P2-CYCLE-A',
          name: 'جذر دورة',
          type: 'أصل',
          parentId: childId,
        ),
      ),
      throwsStateError,
    );
  });
}
