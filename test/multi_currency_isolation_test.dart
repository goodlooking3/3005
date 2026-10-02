import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/currency_repository.dart';
import 'package:wasel/data/local_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  test('allows a posting only when both accounts support its currency', () async {
    final repository = AccountingRepository();
    final currencies = CurrencyRepository();
    await currencies.saveRate(ExchangeRate(
      baseCurrency: 'USD',
      quoteCurrency: 'SAR',
      rate: 3.75,
      effectiveAt: DateTime(2026, 9, 22),
    ));
    final debit = await repository.upsertAccount(const Account(
      code: '1800',
      name: 'حساب متعدد العملات',
      type: 'أصل',
      currencies: ['SAR', 'USD'],
    ));
    final credit = await repository.upsertAccount(const Account(
      code: '4800',
      name: 'إيراد متعدد العملات',
      type: 'إيراد',
      kind: AccountKind.revenue,
      currencies: ['SAR', 'USD'],
    ));

    await repository.insertVoucher(Voucher(
      number: 'MC-1',
      type: VoucherType.journal,
      description: 'قيد بالدولار',
      amount: 10,
      currency: 'USD',
      date: DateTime(2026, 9, 22),
      lines: [
        VoucherLine(accountId: debit, accountName: 'حساب متعدد العملات', debit: 10),
        VoucherLine(accountId: credit, accountName: 'إيراد متعدد العملات', credit: 10),
      ],
    ));

    final row = await (await LocalDatabase.instance.database).query('journal_lines');
    expect(row, hasLength(2));
    expect(row.every((item) => item['currency'] == 'USD'), isTrue);
    expect(row.every((item) => item['base_debit'] != null || item['base_credit'] != null), isTrue);
  });

  test('rejects a posting into an account that does not support its currency', () async {
    final repository = AccountingRepository();
    final debit = await repository.upsertAccount(const Account(code: '1900', name: 'سار فقط', type: 'أصل', currency: 'SAR'));
    final credit = await repository.upsertAccount(const Account(code: '4900', name: 'دخل سار فقط', type: 'إيراد', kind: AccountKind.revenue, currency: 'SAR'));
    expect(
      () => repository.insertVoucher(Voucher(
        number: 'MC-2',
        type: VoucherType.journal,
        description: 'عملة غير مسموحة',
        amount: 10,
        currency: 'USD',
        date: DateTime(2026, 9, 22),
        lines: [
          VoucherLine(accountId: debit, accountName: 'سار فقط', debit: 10),
          VoucherLine(accountId: credit, accountName: 'دخل سار فقط', credit: 10),
        ],
      )),
      throwsA(isA<StateError>()),
    );
  });
}
