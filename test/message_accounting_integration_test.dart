import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/core/connector_models.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/currency_repository.dart';
import 'package:wasel/features/connectors/application/message_accounting_service.dart';
import 'package:wasel/data/local_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  test(
    'posting a message creates a balanced voucher and archives it',
    () async {
      final repository = AccountingRepository();
      await repository.upsertAccount(
        const Account(
          code: 'T-CASH',
          name: 'اختبار الصندوق',
          type: 'صندوق',
          kind: AccountKind.cash,
          currency: 'YER',
          currencies: ['YER', 'SAR'],
        ),
      );
      await repository.upsertAccount(
        const Account(
          code: 'T-REV',
          name: 'اختبار الإيرادات',
          type: 'إيراد',
          kind: AccountKind.revenue,
          currency: 'YER',
          currencies: ['YER', 'SAR'],
        ),
      );
      await CurrencyRepository().saveRate(
        ExchangeRate(
          baseCurrency: 'YER',
          quoteCurrency: 'SAR',
          rate: 0.01,
          effectiveAt: DateTime(2025, 12, 31),
        ),
      );
      final messageId = await repository.addIncomingMessage(
        IncomingMessage(
          provider: 'SMS',
          sender: 'عميل اختبار',
          senderPhone: '700000000',
          body: 'تم استلام 250 ريال، المرجع INT-1',
          receivedAt: DateTime(2026, 1, 1),
          parsedAmount: 250,
          parsedCurrency: 'SAR',
          reference: 'INT-1',
        ),
      );
      final message = (await repository.incomingMessages()).firstWhere(
        (item) => item.id == messageId,
      );

      final voucherId = await MessageAccountingService(repository).postMessage(
        message: message,
        type: VoucherType.receipt,
        debitAccount: 'اختبار الصندوق',
        creditAccount: 'اختبار الإيرادات',
        amountOverride: 275,
        currencyOverride: 'YER',
        descriptionOverride: 'وصف معدل',
      );
      await repository.archiveIncomingMessage(messageId);

      final db = await LocalDatabase.instance.database;
      final voucher = (await db.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [voucherId],
      ))
          .single;
      final lines = await db.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [voucherId],
      );
      final journal = await db.query(
        'journal_entries',
        where: 'voucher_id = ?',
        whereArgs: [voucherId],
      );
      final journalLines = await db.query(
        'journal_lines',
        where: 'journal_entry_id = ?',
        whereArgs: [journal.single['id']],
        orderBy: 'id ASC',
      );
      final audit = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['create_voucher'],
      );
      final postingAudit = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['post_journal_entry'],
      );
      final archived = (await db.query(
        'incoming_messages',
        where: 'id = ?',
        whereArgs: [messageId],
      ))
          .single;
      expect(voucher['amount'], 275.0);
      expect(voucher['currency'], 'YER');
      expect(voucher['base_amount'], 2.75);
      expect(voucher['base_currency'], 'SAR');
      expect(voucher['description'], 'وصف معدل');
      expect(lines.length, 2);
      expect(journal.length, 1);
      expect(journal.single['debit_total'], 2.75);
      expect(journal.single['credit_total'], 2.75);
      expect(journalLines.length, 2);
      expect(
        journalLines.fold<double>(
          0,
          (total, line) => total + (line['base_debit'] as num).toDouble(),
        ),
        2.75,
      );
      expect(
        journalLines.fold<double>(
          0,
          (total, line) => total + (line['base_credit'] as num).toDouble(),
        ),
        2.75,
      );
      expect(audit, isNotEmpty);
      expect(postingAudit, isNotEmpty);
      expect(lines[0]['debit'] == 275.0 || lines[1]['debit'] == 275.0, isTrue);
      expect(archived['archived'], 1);
      expect(
        () => db.insert('journal_lines', {
          'journal_entry_id': journal.single['id'],
          'account_name': 'سطر غير صالح',
          'debit': 1.0,
          'credit': 1.0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('posting rejects a voucher whose lines do not equal its amount',
      () async {
    final repository = AccountingRepository();
    final debitId = await repository.upsertAccount(
      const Account(code: 'T-VALID-1', name: 'حساب مدين', type: 'أصل'),
    );
    final creditId = await repository.upsertAccount(
      const Account(code: 'T-VALID-2', name: 'حساب دائن', type: 'أصل'),
    );
    final voucher = Voucher(
      number: 'INVALID-AMOUNT',
      type: VoucherType.journal,
      description: 'اختبار عدم تطابق',
      amount: 100,
      currency: 'SAR',
      date: DateTime(2026, 1, 2),
      lines: [
        VoucherLine(accountId: debitId, accountName: 'حساب مدين', debit: 99),
        VoucherLine(accountId: creditId, accountName: 'حساب دائن', credit: 99),
      ],
    );
    await expectLater(repository.insertVoucher(voucher), throwsArgumentError);
  });
}
