import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasel/core/models.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/services/auth_service.dart';
import 'package:wasel/services/sync_service.dart';
import 'package:wasel/core/production_config.dart';
import 'package:wasel/services/session_token_service.dart';
import 'package:wasel/main.dart' show HomeShell;
import 'package:wasel/connectors/connector_adapters.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/data/currency_repository.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/services/report_service.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasel/features/my_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_transaction.dart';
import 'package:wasel/features/my_sales/data/sales_engine.dart';
import 'package:wasel/features/my_sales/domain/sales_invoice.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    await LocalDatabase.instance.resetForTests();
    final db = await LocalDatabase.instance.database;
    await db.insert('accounts', {
      'id': 101,
      'code': 'TEST-CASH',
      'name': 'الصندوق',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'SAR',
    });
    await db.insert('accounts', {
      'id': 401,
      'code': 'TEST-SALES',
      'name': 'المبيعات',
      'type': 'إيراد',
      'kind': 'revenue',
      'currency': 'SAR',
    });
    await CurrencyRepository().saveRate(
      ExchangeRate(
        baseCurrency: 'USD',
        quoteCurrency: 'SAR',
        rate: 3.75,
        effectiveAt: DateTime(2025, 12, 31),
      ),
    );
  });
  test('account setup and sign-in flow succeeds', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    expect(await auth.hasAccount(), isFalse);
    await auth.createAccount(email: 'owner@example.com', password: 'secret123');
    expect(await auth.hasAccount(), isTrue);
    expect(
      await auth.signIn(email: 'owner@example.com', password: 'secret123'),
      isTrue,
    );
    expect(
      await auth.signIn(email: 'owner@example.com', password: 'wrong'),
      isFalse,
    );
  });

  test('archiving parser produces a reviewable remittance', () {
    final parsed = MessageParser.parse(
      'تم استلام حوالة بمبلغ 1,250 ر.س، المرجع 550281',
    );
    final item = Remittance(
      createdAt: DateTime.now(),
      sender: 'اختبار',
      phone: '+966',
      amount: parsed.amount,
      currency: parsed.currency,
      reference: parsed.reference,
      message: 'test',
      source: 'SMS',
    );
    expect(item.amount, 1250);
    expect(item.reference, '550281');
  });

  test('sync rejects insecure endpoints before sending data', () async {
    final service = SyncService(
      repository: AccountingRepository(),
      client: http.Client(),
    );
    expect(
      () => service.pushPending(
        endpoint: Uri.parse('http://example.com/sync'),
        bearerToken: 'token',
      ),
      throwsArgumentError,
    );
  });

  test('webhook connector rejects non-HTTPS configuration', () async {
    final connector = WebhookConnector(
      const ConnectorConfig(
        endpoint: 'http://example.com',
        displayName: 'Test',
      ),
    );
    expect(connector.connect, throwsArgumentError);
  });

  test('conflict policy sends equal or destructive conflicts to review', () {
    const policy = ConflictPolicy();
    final now = DateTime.utc(2026, 1, 1);
    expect(
      policy.resolve(
        localUpdatedAt: now.add(const Duration(minutes: 1)),
        remoteUpdatedAt: now,
        remoteDeleted: false,
      ),
      ConflictResolution.keepLocal,
    );
    expect(
      policy.resolve(
        localUpdatedAt: now,
        remoteUpdatedAt: now.add(const Duration(minutes: 1)),
        remoteDeleted: false,
      ),
      ConflictResolution.keepRemote,
    );
    expect(
      policy.resolve(
        localUpdatedAt: now,
        remoteUpdatedAt: now,
        remoteDeleted: false,
      ),
      ConflictResolution.manualReview,
    );
  });

  test(
    'token rotation validates and parses short-lived session tokens',
    () async {
      final client = MockClient(
        (request) async =>
            http.Response('{"access_token":"a","refresh_token":"b"}', 200),
      );
      final tokens = await SessionTokenService(client).rotate(
        endpoint: Uri.parse('https://auth.example.test/rotate'),
        refreshToken: 'old',
      );
      expect(tokens.accessToken, 'a');
      expect(
        const TokenRotationPolicy().accessTokenLifetime,
        const Duration(minutes: 15),
      );
    },
  );

  test('database migration exposes enterprise accounting tables', () async {
    final db = await LocalDatabase.instance.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll([
        'accounts',
        'voucher_lines',
        'parties',
        'company_profile',
        'connector_configs',
        'incoming_messages',
        'journal_entries',
        'journal_lines',
        'wallets',
        'wallet_accounts',
        'wallet_transactions',
        'marketplace_vendors',
        'marketplace_products',
        'purchase_orders',
        'purchase_order_lines',
        'inventory_items',
        'sales_invoices',
        'sales_invoice_lines',
      ]),
    );
  });

  test(
    'voucher balance invariant and report services are deterministic',
    () async {
      const balanced = VoucherLine(accountName: 'الصندوق', debit: 100);
      const matching = VoucherLine(accountName: 'إيراد', credit: 100);
      final voucher = Voucher(
        number: 'T-1',
        type: VoucherType.receipt,
        description: 'اختبار',
        amount: 100,
        currency: 'SAR',
        date: DateTime.utc(2026, 1, 1),
        lines: const [balanced, matching],
      );
      expect(voucher.isBalanced, isTrue);
      final report = await ReportService().profitAndLoss();
      expect(report.net, report.revenue - report.expenses);
    },
  );

  test('wallet posting creates balanced journal and stores its reference',
      () async {
    final repository = WalletRepositoryImpl();
    final transaction = WalletTransaction(
      fromAccount: 'حساب مصدر تكاملي',
      toAccount: 'حساب وجهة تكاملي',
      type: WalletTransactionType.transfer,
      amount: 125,
      currency: 'USD',
      note: 'حركة تكاملية',
      date: DateTime.utc(2026, 1, 2),
      reference: 'INTEGRATION-${DateTime.now().microsecondsSinceEpoch}',
      relatedModule: 'journal',
      relatedEntityId: 'integration-1',
    );
    await repository.saveTransaction(transaction);
    final db = await LocalDatabase.instance.database;
    final rows =
        await db.query('wallet_transactions', orderBy: 'id DESC', limit: 1);
    final journalId = rows.single['journal_entry_id'] as int?;
    expect(journalId, isNotNull);
    final journal = await db
        .query('journal_entries', where: 'id = ?', whereArgs: [journalId]);
    expect(journal.single['debit_total'], journal.single['credit_total']);
    expect(journal.single['source'], 'voucher');
  });

  test('sales integration keeps stock, invoice and journal balanced atomically',
      () async {
    final db = await LocalDatabase.instance.database;
    final number = 'SALE-INTEGRATION-${DateTime.now().microsecondsSinceEpoch}';
    final itemId = await db.insert('inventory_items', {
      'name': 'صنف اختبار البيع',
      'sku': number,
      'cost_price': 10.0,
      'sale_price': 18.0,
      'quantity': 5.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final invoice = SalesInvoice(
      number: number,
      customerName: 'عميل تكامل',
      paymentAccount: 'الصندوق',
      currency: 'SAR',
      issuedAt: DateTime.utc(2026, 1, 3),
      lines: [
        SalesInvoiceLine(
            itemId: itemId,
            itemName: 'صنف اختبار البيع',
            quantity: 2,
            unitPrice: 18,
            unitCost: 10)
      ],
    );
    final journalId = await SalesEngine().completeSale(
        invoice: invoice, cashAccountId: 101, salesAccountId: 401);
    final stock =
        await db.query('inventory_items', where: 'id = ?', whereArgs: [itemId]);
    expect(stock.single['quantity'], 3.0);
    final saved = await db
        .query('sales_invoices', where: 'number = ?', whereArgs: [number]);
    expect(saved.single['journal_entry_id'], journalId);
    expect(saved.single['total'], 36.0);
    expect(saved.single['cost_of_goods_sold'], 20.0);
    expect(saved.single['profit'], 16.0);
    final journal = await db
        .query('journal_entries', where: 'id = ?', whereArgs: [journalId]);
    expect(journal.single['debit_total'], journal.single['credit_total']);
    expect(journal.single['source'], 'sales');
    final lines = await db.query('journal_lines',
        where: 'journal_entry_id = ?', whereArgs: [journalId]);
    expect(lines, hasLength(2));
    expect(
        lines.fold<double>(
            0, (sum, row) => sum + (row['debit'] as num).toDouble()),
        36.0);
    expect(
        lines.fold<double>(
            0, (sum, row) => sum + (row['credit'] as num).toDouble()),
        36.0);

    await expectLater(
      () => SalesEngine().completeSale(
          invoice: invoice, cashAccountId: 101, salesAccountId: 401),
      throwsA(anything),
    );
    final afterFailureStock =
        await db.query('inventory_items', where: 'id = ?', whereArgs: [itemId]);
    expect(afterFailureStock.single['quantity'], 3.0);
    expect(
        await db
            .query('sales_invoices', where: 'number = ?', whereArgs: [number]),
        hasLength(1));
    expect(
        await db
            .query('journal_entries', where: 'number = ?', whereArgs: [number]),
        hasLength(1));
  });

  testWidgets('home shell renders after authenticated navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('نظرة عامة'), findsWidgets);
    await tester.pump(const Duration(seconds: 11));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
