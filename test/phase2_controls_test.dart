import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_authorization.dart';
import 'package:wasel/data/accounting_period_repository.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/currency_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/services/auth_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await LocalDatabase.instance.resetForTests();
    SharedPreferences.setMockInitialValues({});
  });

  Future<int> addAccount(
    AccountingRepository repository, {
    required String code,
    required String name,
    required AccountKind kind,
    String currency = 'SAR',
    double openingBalance = 0,
  }) =>
      repository.upsertAccount(
        Account(
          code: code,
          name: name,
          type: kind.name,
          kind: kind,
          currency: currency,
          currencies: [currency],
          balance: openingBalance,
        ),
      );

  test(
      'recomputes balances from journal by currency and reconciles base totals',
      () async {
    final repository = AccountingRepository();
    final usdCash = await addAccount(
      repository,
      code: 'P2-USD-CASH',
      name: 'نقد USD',
      kind: AccountKind.cash,
      currency: 'USD',
    );
    final sarRevenue = await addAccount(
      repository,
      code: 'P2-SAR-REV',
      name: 'إيراد SAR',
      kind: AccountKind.revenue,
    );
    await CurrencyRepository().saveRate(
      ExchangeRate(
        baseCurrency: 'USD',
        quoteCurrency: 'SAR',
        rate: 3.75,
        effectiveAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await repository.insertVoucher(
      Voucher(
        number: 'P2-FX-1',
        type: VoucherType.journal,
        description: 'اختبار تقويم متعدد العملات',
        amount: 37.5,
        currency: 'SAR',
        date: DateTime.utc(2026, 10, 5),
        lines: [
          VoucherLine(
            accountId: usdCash,
            accountName: 'نقد USD',
            debit: 10,
            currency: 'USD',
          ),
          VoucherLine(
            accountId: sarRevenue,
            accountName: 'إيراد SAR',
            credit: 37.5,
            currency: 'SAR',
          ),
        ],
      ),
    );

    final balances = await repository.accountBalances();
    final cash = balances.singleWhere((row) => row.accountId == usdCash);
    final revenue = balances.singleWhere((row) => row.accountId == sarRevenue);
    expect(cash.currency, 'USD');
    expect(cash.balance, 10);
    expect(cash.baseBalance, 37.5);
    expect(revenue.balance, 37.5);
    expect(revenue.baseBalance, 37.5);
    final summary = await repository.summary();
    expect(summary.totalDebits, 37.5);
    expect(summary.totalCredits, 37.5);
    expect(summary.cashBalance, 37.5);
  });

  test('serializes document numbers across concurrent requests', () async {
    final repository = AccountingRepository();
    final numbers = await Future.wait(List.generate(
      20,
      (_) => repository.nextVoucherNumber(
        VoucherType.journal,
        date: DateTime(2026, 4, 1),
      ),
    ));
    expect(numbers.toSet(), hasLength(20));
    expect(numbers.first, 'JV-2026-000001');
    expect(numbers.last, 'JV-2026-000020');
  });

  test('periods reject overlap, close only balanced books, and block posting',
      () async {
    final repository = AccountingRepository();
    const periods = AccountingPeriodRepository();
    final cash = await addAccount(
      repository,
      code: 'P2-PER-CASH',
      name: 'صندوق الفترة',
      kind: AccountKind.cash,
    );
    final revenue = await addAccount(
      repository,
      code: 'P2-PER-REV',
      name: 'إيراد الفترة',
      kind: AccountKind.revenue,
    );
    final firstPeriod = await periods.createPeriod(
      name: '2026',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
    );
    await expectLater(
      periods.createPeriod(
        name: 'متداخلة',
        startDate: DateTime(2026, 12, 1),
        endDate: DateTime(2027, 1, 31),
      ),
      throwsStateError,
    );
    await repository.insertVoucher(
      Voucher(
        number: 'P2-PERIOD-ENTRY',
        type: VoucherType.journal,
        description: 'قيد قبل الإقفال',
        amount: 25,
        currency: 'SAR',
        date: DateTime(2026, 8, 1),
        lines: [
          VoucherLine(accountId: cash, accountName: 'صندوق الفترة', debit: 25),
          VoucherLine(
              accountId: revenue, accountName: 'إيراد الفترة', credit: 25),
        ],
      ),
    );
    await periods.closePeriod(firstPeriod);
    final db = await LocalDatabase.instance.database;
    await expectLater(
      db.update(
        'accounting_periods',
        {'name': 'محاولة تعديل'},
        where: 'id = ?',
        whereArgs: [firstPeriod],
      ),
      throwsA(anything),
    );
    await expectLater(
      repository.insertVoucher(
        Voucher(
          number: 'P2-CLOSED-ENTRY',
          type: VoucherType.journal,
          description: 'محاولة ترحيل لفترة مقفلة',
          amount: 1,
          currency: 'SAR',
          date: DateTime(2026, 9, 1),
          lines: [
            VoucherLine(accountId: cash, accountName: 'صندوق الفترة', debit: 1),
            VoucherLine(
                accountId: revenue, accountName: 'إيراد الفترة', credit: 1),
          ],
        ),
      ),
      throwsA(anything),
    );
    await periods.createPeriod(
      name: '2027',
      startDate: DateTime(2027, 1, 1),
      endDate: DateTime(2027, 12, 31),
    );
  });

  test('reversal is append-only and idempotent', () async {
    final repository = AccountingRepository();
    final cash = await addAccount(
      repository,
      code: 'P2-REV-CASH',
      name: 'نقد العكس',
      kind: AccountKind.cash,
    );
    final revenue = await addAccount(
      repository,
      code: 'P2-REV-REV',
      name: 'إيراد العكس',
      kind: AccountKind.revenue,
    );
    await repository.insertVoucher(
      Voucher(
        number: 'P2-REV-SOURCE',
        type: VoucherType.journal,
        description: 'قيد أصلي',
        amount: 81,
        currency: 'SAR',
        date: DateTime(2026, 6, 1),
        lines: [
          VoucherLine(accountId: cash, accountName: 'نقد العكس', debit: 81),
          VoucherLine(
              accountId: revenue, accountName: 'إيراد العكس', credit: 81),
        ],
      ),
    );
    final source =
        (await repository.journalEntries(query: 'P2-REV-SOURCE')).single;
    final reversalId = await repository.reverseJournalEntry(
      journalEntryId: source.id,
      reversalNumber: 'P2-REV-1',
      reversalDate: DateTime(2026, 6, 2),
      reason: 'إلغاء العملية',
    );
    final reversed =
        (await repository.journalEntries(query: 'P2-REV-1')).single;
    expect(reversed.id, reversalId);
    expect(reversed.reversalOfId, source.id);
    expect(reversed.debitTotal, source.creditTotal);
    expect(reversed.creditTotal, source.debitTotal);
    final db = await LocalDatabase.instance.database;
    final sourceLines = await db.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [source.id],
    );
    final reversalLines = await db.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [reversalId],
    );
    expect(reversalLines[0]['debit'], sourceLines[0]['credit']);
    expect(reversalLines[0]['credit'], sourceLines[0]['debit']);
    await expectLater(
      db.update('journal_entries', {'description': 'تعديل'},
          where: 'id = ?', whereArgs: [source.id]),
      throwsA(anything),
    );
    await expectLater(
      repository.reverseJournalEntry(
        journalEntryId: source.id,
        reversalNumber: 'P2-REV-2',
        reversalDate: DateTime(2026, 6, 3),
        reason: 'عكس مكرر',
      ),
      throwsStateError,
    );
  });

  test('RBAC denies sensitive calls and direct SQL cannot escalate role',
      () async {
    final db = await LocalDatabase.instance.database;
    final repository = AccountingRepository();
    await db.update('user_profile', {'role': 'viewer'},
        where: 'id = ?', whereArgs: [1]);

    expect(await repository.accounts(), isEmpty);
    await expectLater(
      repository.upsertAccount(
        const Account(code: 'P2-DENIED', name: 'ممنوع', type: 'أصل'),
      ),
      throwsA(isA<AuthorizationDeniedException>()),
    );
    await expectLater(
        repository.audit(), throwsA(isA<AuthorizationDeniedException>()));
    await expectLater(
      db.insert('vouchers', {
        'number': 'P2-RAW-DENIED',
        'type': 'journal',
        'description': 'direct SQL',
        'amount': 1.0,
        'currency': 'SAR',
        'date': '2026-10-05',
      }),
      throwsA(anything),
    );
    await expectLater(
      db.update('user_profile', {'role': 'admin'},
          where: 'id = ?', whereArgs: [1]),
      throwsA(anything),
    );
    final denials = await db.query(
      'audit_log',
      where: 'action = ?',
      whereArgs: ['authorization.denied'],
    );
    expect(denials, isNotEmpty);
  });

  test('currency rounding uses one documented base tolerance', () async {
    final repository = AccountingRepository();
    final usdCash = await addAccount(
      repository,
      code: 'P2-ROUND-USD',
      name: 'نقد التقريب USD',
      kind: AccountKind.cash,
      currency: 'USD',
    );
    final sarRevenue = await addAccount(
      repository,
      code: 'P2-ROUND-SAR',
      name: 'إيراد التقريب SAR',
      kind: AccountKind.revenue,
    );
    await CurrencyRepository().saveRate(
      ExchangeRate(
        baseCurrency: 'USD',
        quoteCurrency: 'SAR',
        rate: 3.75,
        effectiveAt: DateTime.utc(2026, 1, 1),
      ),
    );
    Voucher build(String number, double usdDebit) => Voucher(
          number: number,
          type: VoucherType.journal,
          description: 'اختبار tolerance',
          amount: 37.5,
          currency: 'SAR',
          date: DateTime.utc(2026, 10, 5),
          lines: [
            VoucherLine(
              accountId: usdCash,
              accountName: 'نقد التقريب USD',
              debit: usdDebit,
              currency: 'USD',
            ),
            VoucherLine(
              accountId: sarRevenue,
              accountName: 'إيراد التقريب SAR',
              credit: 37.5,
              currency: 'SAR',
            ),
          ],
        );

    await repository.insertVoucher(build('P2-ROUND-OK', 10.0000001));
    final entry =
        (await repository.journalEntries(query: 'P2-ROUND-OK')).single;
    expect((entry.debitTotal - entry.creditTotal).abs(),
        lessThanOrEqualTo(accountingTolerance));
    await expectLater(
      repository.insertVoucher(build('P2-ROUND-BAD', 10.000001)),
      throwsA(anything),
    );
    final db = await LocalDatabase.instance.database;
    expect(
      await db
          .query('vouchers', where: 'number = ?', whereArgs: ['P2-ROUND-BAD']),
      isEmpty,
    );
  });

  test('receipt and payment enforce official cash direction', () async {
    final repository = AccountingRepository();
    final cash = await addAccount(
      repository,
      code: 'P2-DIR-CASH',
      name: 'صندوق الاتجاه',
      kind: AccountKind.cash,
    );
    final bank = await addAccount(
      repository,
      code: 'P2-DIR-BANK',
      name: 'بنك الاتجاه',
      kind: AccountKind.bank,
    );
    final customer = await addAccount(
      repository,
      code: 'P2-DIR-CUST',
      name: 'ذمم الاتجاه',
      kind: AccountKind.customer,
    );
    final expense = await addAccount(
      repository,
      code: 'P2-DIR-EXP',
      name: 'مصروف الاتجاه',
      kind: AccountKind.expense,
    );
    await expectLater(
      repository.insertVoucher(
        Voucher(
          number: 'P2-DIR-BAD-RECEIPT',
          type: VoucherType.receipt,
          description: 'قبض بلا نقد مدين',
          amount: 10,
          currency: 'SAR',
          date: DateTime(2026, 10, 5),
          lines: [
            VoucherLine(
                accountId: customer, accountName: 'ذمم الاتجاه', debit: 10),
            VoucherLine(
                accountId: expense, accountName: 'مصروف الاتجاه', credit: 10),
          ],
        ),
      ),
      throwsStateError,
    );
    await repository.insertVoucher(
      Voucher(
        number: 'P2-DIR-RECEIPT',
        type: VoucherType.receipt,
        description: 'قبض صحيح',
        amount: 10,
        currency: 'SAR',
        date: DateTime(2026, 10, 5),
        lines: [
          VoucherLine(accountId: cash, accountName: 'صندوق الاتجاه', debit: 10),
          VoucherLine(
              accountId: customer, accountName: 'ذمم الاتجاه', credit: 10),
        ],
      ),
    );
    await repository.insertVoucher(
      Voucher(
        number: 'P2-DIR-PAYMENT',
        type: VoucherType.payment,
        description: 'صرف صحيح',
        amount: 10,
        currency: 'SAR',
        date: DateTime(2026, 10, 5),
        lines: [
          VoucherLine(
              accountId: expense, accountName: 'مصروف الاتجاه', debit: 10),
          VoucherLine(accountId: bank, accountName: 'بنك الاتجاه', credit: 10),
        ],
      ),
    );
  });

  test('passwords use salted PBKDF2 and legacy SHA256 upgrades on sign-in',
      () async {
    final auth = AuthService();
    await auth.createAccount(
      email: 'phase2@example.test',
      password: 'secure-pass-42',
    );
    var preferences = await SharedPreferences.getInstance();
    final created = preferences.getString('wasel_auth_password')!;
    expect(created, startsWith('pbkdf2-sha256:150000:'));
    expect(created, isNot(contains('secure-pass-42')));
    expect(
      await auth.signIn(
          email: 'phase2@example.test', password: 'secure-pass-42'),
      isTrue,
    );
    expect(
      await auth.signIn(email: 'phase2@example.test', password: 'wrong-pass'),
      isFalse,
    );

    final legacyDigest = await Sha256().hash(utf8.encode('legacy-pass-42'));
    SharedPreferences.setMockInitialValues({
      'wasel_auth_configured': true,
      'wasel_auth_email': 'legacy@example.test',
      'wasel_auth_phone': '',
      'wasel_auth_password': 'sha256:${base64UrlEncode(legacyDigest.bytes)}',
      'wasel_auth_display_name': 'مالك',
    });
    final legacyAuth = AuthService();
    expect(
      await legacyAuth.signIn(
        email: 'legacy@example.test',
        password: 'legacy-pass-42',
      ),
      isTrue,
    );
    preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('wasel_auth_password'),
      startsWith('pbkdf2-sha256:150000:'),
    );
  });
}
