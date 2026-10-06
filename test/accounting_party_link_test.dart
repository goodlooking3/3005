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

  test('party is linked to its analytical account and journal lines', () async {
    final repository = AccountingRepository();
    final customerAccountId = await repository.upsertAccount(const Account(
      code: '1210',
      name: 'عملاء نقديون',
      type: 'عميل',
      kind: AccountKind.customer,
    ));
    final cashAccountId = await repository.upsertAccount(const Account(
      code: '1110',
      name: 'الصندوق',
      type: 'صندوق',
      kind: AccountKind.cash,
    ));
    final partyId = await repository.insertParty(Party(
      accountId: customerAccountId,
      name: 'عميل مرتبط',
      type: 'customer',
      currency: 'SAR',
    ));

    final parties = await repository.parties();
    expect(parties.single.accountId, customerAccountId);

    await repository.insertVoucher(Voucher(
      number: 'PARTY-LINK-1',
      type: VoucherType.receipt,
      description: 'تحصيل من عميل مرتبط',
      amount: 100,
      currency: 'SAR',
      date: DateTime(2026, 10, 4),
      lines: [
        VoucherLine(
          accountId: customerAccountId,
          partyId: partyId,
          accountName: 'عملاء نقديون',
          credit: 100,
          currency: 'SAR',
          partyName: 'عميل مرتبط',
        ),
        VoucherLine(
          accountId: cashAccountId,
          accountName: 'الصندوق',
          debit: 100,
          currency: 'SAR',
        ),
      ],
    ));

    final db = await LocalDatabase.instance.database;
    expect(
        (await db.query('voucher_lines', where: 'party_id IS NOT NULL'))
            .single['party_id'],
        partyId);
    expect(
        (await db.query('journal_lines', where: 'party_id IS NOT NULL'))
            .single['party_id'],
        partyId);
  });

  test('voucher stores an optional manual due date on its journal entry',
      () async {
    final repository = AccountingRepository();
    final customerAccountId = await repository.upsertAccount(const Account(
      code: '1211',
      name: 'ذمم العملاء',
      type: 'عميل',
      kind: AccountKind.customer,
    ));
    final revenueAccountId = await repository.upsertAccount(const Account(
      code: '4100',
      name: 'الإيرادات',
      type: 'إيراد',
      kind: AccountKind.revenue,
    ));
    final partyId = await repository.insertParty(Party(
      accountId: customerAccountId,
      name: 'عميل آجل',
      type: 'customer',
      currency: 'SAR',
    ));
    final dueDate = DateTime(2026, 10, 20);

    await repository.insertVoucher(Voucher(
      number: 'DUE-DATE-1',
      type: VoucherType.journal,
      description: 'فاتورة آجلة',
      amount: 125,
      currency: 'SAR',
      date: DateTime(2026, 10, 6),
      dueDate: dueDate,
      lines: [
        VoucherLine(
          accountId: customerAccountId,
          partyId: partyId,
          accountName: 'ذمم العملاء',
          debit: 125,
          partyName: 'عميل آجل',
        ),
        VoucherLine(
          accountId: revenueAccountId,
          accountName: 'الإيرادات',
          credit: 125,
        ),
      ],
    ));

    final db = await LocalDatabase.instance.database;
    final row = (await db.query('journal_entries',
            where: 'number = ?', whereArgs: ['DUE-DATE-1']))
        .single;
    expect(DateTime.parse(row['due_date']! as String), dueDate);
  });

  test('new party requires a matching active analytical account', () async {
    final repository = AccountingRepository();
    final assetId = await repository.upsertAccount(const Account(
      code: '1901',
      name: 'أصل غير تحليلي',
      type: 'أصل',
      kind: AccountKind.asset,
    ));

    await expectLater(
      repository.insertParty(Party(
        accountId: assetId,
        name: 'طرف بحساب خاطئ',
        type: 'customer',
      )),
      throwsStateError,
    );
  });
}
