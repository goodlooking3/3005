import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/accounting_policy_repository.dart';
import 'package:wasel/data/local_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async => LocalDatabase.instance.resetForTests());

  test('policy defaults are general and persisted choices reload', () async {
    const repository = AccountingPolicyRepository();
    final initial = await repository.load();
    expect(initial.reportingFramework, ReportingFramework.general);
    expect(initial.agingDateBasis, AgingDateBasis.dueDateWhenAvailable);
    expect(initial.fiscalYearStartMonth, 1);

    await repository.save(const AccountingPolicySettings(
      reportingFramework: ReportingFramework.local,
      agingDateBasis: AgingDateBasis.dueDateOnly,
      fiscalYearStartMonth: 7,
      jurisdictionCode: 'SA',
    ));
    final saved = await repository.load();
    expect(saved.reportingFramework, ReportingFramework.local);
    expect(saved.agingDateBasis, AgingDateBasis.dueDateOnly);
    expect(saved.fiscalYearStartMonth, 7);
    expect(saved.jurisdictionCode, 'SA');

    final db = await LocalDatabase.instance.database;
    expect(
      (await db.query('audit_log',
              where: 'entity_type = ?',
              whereArgs: ['accounting_policy_settings']))
          .length,
      greaterThanOrEqualTo(3),
    );
  });

  test('invalid fiscal-year month cannot be saved', () async {
    await expectLater(
      const AccountingPolicyRepository().save(
        const AccountingPolicySettings(fiscalYearStartMonth: 13),
      ),
      throwsArgumentError,
    );
  });

  test('local reporting profile requires a two-letter jurisdiction code',
      () async {
    await expectLater(
      const AccountingPolicyRepository().save(const AccountingPolicySettings(
        reportingFramework: ReportingFramework.local,
      )),
      throwsArgumentError,
    );
  });

  test('base currency is configurable before posting and locked afterward',
      () async {
    final repository = AccountingRepository();
    await repository.saveCompany(const CompanyProfile(
      name: 'اختبار منشأة',
      baseCurrency: 'USD',
    ));
    expect((await repository.company())?.baseCurrency, 'USD');

    await repository.upsertAccount(const Account(
      code: '10001',
      name: 'نقد',
      type: 'أصل',
      kind: AccountKind.cash,
      currency: 'USD',
      currencies: ['USD'],
    ));
    await repository.upsertAccount(const Account(
      code: '40001',
      name: 'إيراد',
      type: 'إيراد',
      kind: AccountKind.revenue,
      currency: 'USD',
      currencies: ['USD'],
    ));
    final accounts = await repository.accounts();
    final cash = accounts.singleWhere((item) => item.code == '10001');
    final revenue = accounts.singleWhere((item) => item.code == '40001');
    await repository.insertVoucher(Voucher(
      number: 'CCY-LOCK-1',
      type: VoucherType.journal,
      description: 'اختبار قفل العملة',
      amount: 10,
      currency: 'USD',
      date: DateTime.utc(2026, 10, 7),
      lines: [
        VoucherLine(
          accountId: cash.id,
          accountName: cash.name,
          debit: 10,
          currency: 'USD',
        ),
        VoucherLine(
          accountId: revenue.id,
          accountName: revenue.name,
          credit: 10,
          currency: 'USD',
        ),
      ],
    ));

    await expectLater(
      repository.saveCompany(const CompanyProfile(
        name: 'اختبار منشأة',
        baseCurrency: 'SAR',
      )),
      throwsStateError,
    );
  });
}
