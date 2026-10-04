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
          debit: 100,
          currency: 'SAR',
          partyName: 'عميل مرتبط',
        ),
        VoucherLine(
          accountId: cashAccountId,
          accountName: 'الصندوق',
          credit: 100,
          currency: 'SAR',
        ),
      ],
    ));

    final db = await LocalDatabase.instance.database;
    expect((await db.query('voucher_lines', where: 'party_id IS NOT NULL')).single['party_id'], partyId);
    expect((await db.query('journal_lines', where: 'party_id IS NOT NULL')).single['party_id'], partyId);
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
