import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_sales/data/sales_engine.dart';
import 'package:wasel/features/my_sales/presentation/screens/sales_invoice_screen.dart';
import 'package:wasel/features/my_sales/presentation/screens/sales_reversals_screen.dart';

void main() {
  late int cashSarId;
  late int cashMultiCurrencyId;
  late int cashGroupId;
  late int sarItemId;
  late int fractionalItemId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await LocalDatabase.instance.resetForTests();
    final db = await LocalDatabase.instance.database;
    cashSarId = await _addAccount(
      db,
      code: '1010',
      name: 'الصندوق بالريال',
      kind: 'cash',
      currency: 'SAR',
      currencies: const ['SAR'],
    );
    cashMultiCurrencyId = await _addAccount(
      db,
      code: '1020',
      name: 'صندوق متعدد العملات',
      kind: 'cash',
      currency: 'SAR',
      currencies: const ['SAR', 'USD'],
    );
    cashGroupId = await _addAccount(
      db,
      code: '1000',
      name: 'مجموعة الصناديق',
      kind: 'cash',
      currency: 'SAR',
      currencies: const ['SAR', 'USD'],
      isGroup: true,
    );
    await _addAccount(
      db,
      code: '4000',
      name: 'إيرادات الريال',
      kind: 'revenue',
      currency: 'SAR',
      currencies: const ['SAR'],
    );
    await _addAccount(
      db,
      code: '4010',
      name: 'إيرادات الدولار',
      kind: 'revenue',
      currency: 'USD',
      currencies: const ['USD'],
    );
    sarItemId = await db.insert('inventory_items', {
      'name': 'صنف الريال',
      'sku': 'SAR-ITEM',
      'cost_price': 8.0,
      'sale_price': 18.0,
      'quantity': 8.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    fractionalItemId = await db.insert('inventory_items', {
      'name': 'صنف كسري',
      'sku': 'SAR-FRACTIONAL',
      'cost_price': 4.0,
      'sale_price': 8.5,
      'quantity': 0.5,
      'low_stock_threshold': 0.1,
      'currency': 'SAR',
    });
    await db.insert('inventory_items', {
      'name': 'صنف الدولار',
      'sku': 'USD-ITEM',
      'cost_price': 4.0,
      'sale_price': 9.0,
      'quantity': 5.0,
      'low_stock_threshold': 1.0,
      'currency': 'USD',
    });
  });

  testWidgets('invoice respects currency permissions and fits narrow and wide layouts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: SalesInvoiceScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final cashField = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey('sale-cash-account')),
    );
    final cashDropdown = _dropdownButton(tester, 'sale-cash-account');
    expect(cashField.initialValue, cashSarId);
    expect(cashDropdown.items!.map((item) => item.value), contains(cashMultiCurrencyId));
    expect(cashDropdown.items!.map((item) => item.value), isNot(contains(cashGroupId)));
    expect(tester.takeException(), isNull);

    for (final itemId in [sarItemId, fractionalItemId]) {
      final addButton = find.byKey(ValueKey('sale-add-$itemId'));
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
    }
    expect(find.text('22.25 SAR'), findsOneWidget);
    expect(find.text('0.5 × 8.50 = 4.25 SAR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sale-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD — دولار أمريكي').last);
    await tester.pumpAndSettle();
    expect(find.text('صنف الدولار'), findsOneWidget);
    expect(find.text('صنف الريال'), findsNothing);
    final usdCashDropdown = _dropdownButton(tester, 'sale-cash-account');
    expect(usdCashDropdown.items!.map((item) => item.value), contains(cashMultiCurrencyId));
    expect(usdCashDropdown.items!.map((item) => item.value), isNot(contains(cashSarId)));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('invoice does not assume a currency when none is active',
      (tester) async {
    final db = await LocalDatabase.instance.database;
    await db.update('currencies', {'active': 0});
    await tester.pumpWidget(const MaterialApp(home: SalesInvoiceScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('لا توجد عملات نشطة'), findsOneWidget);
    expect(find.byKey(const ValueKey('sale-currency')), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice defaults to the first active currency when SAR is inactive',
      (tester) async {
    final db = await LocalDatabase.instance.database;
    await db.update('currencies', {'active': 0});
    await db.update(
      'currencies',
      {'active': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
    await tester.pumpWidget(const MaterialApp(home: SalesInvoiceScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final currencyField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('sale-currency')),
    );
    expect(currencyField.initialValue, 'USD');
    final cashField = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey('sale-cash-account')),
    );
    expect(cashField.initialValue, cashMultiCurrencyId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return details remain usable on a narrow phone viewport',
      (tester) async {
    final db = await LocalDatabase.instance.database;
    final itemId = await db.insert('inventory_items', {
      'name': 'صنف اختبار المرتجع',
      'sku': 'RETURN-RESPONSIVE',
      'cost_price': 4.0,
      'sale_price': 9.0,
      'quantity': 3.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    const invoiceNumber = 'RETURN-RESPONSIVE-INVOICE';
    await db.insert('sales_invoices', {
      'number': invoiceNumber,
      'customer_name': 'عميل اختبار',
      'payment_account': 'الصندوق بالريال',
      'currency': 'SAR',
      'total': 18.0,
      'cost_of_goods_sold': 8.0,
      'profit': 10.0,
      'issued_at': DateTime(2026, 10, 4).toIso8601String(),
      'status': 'posted',
    });
    await db.insert('sales_invoice_lines', {
      'invoice_number': invoiceNumber,
      'item_id': itemId,
      'item_name': 'صنف اختبار المرتجع',
      'quantity': 2.0,
      'unit_price': 9.0,
      'unit_cost': 4.0,
      'line_total': 18.0,
    });
    final invoice = (await db.query(
      'sales_invoices',
      where: 'number = ?',
      whereArgs: [invoiceNumber],
    ))
        .single;

    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: SalesReturnDetailsScreen(invoice: invoice, engine: SalesEngine()),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('صنف اختبار المرتجع'), findsOneWidget);
    expect(find.text('ترحيل المرتجع الجزئي'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

DropdownButton<int> _dropdownButton(WidgetTester tester, String key) =>
    tester.widget<DropdownButton<int>>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(DropdownButton<int>),
      ),
    );

Future<int> _addAccount(
  Database db, {
  required String code,
  required String name,
  required String kind,
  required String currency,
  required List<String> currencies,
  bool isGroup = false,
}) async {
  final id = await db.insert('accounts', {
    'code': code,
    'name': name,
    'type': kind == 'revenue' ? 'إيراد' : 'أصل',
    'kind': kind,
    'currency': currency,
    'is_group': isGroup ? 1 : 0,
    'active': 1,
  });
  for (final supportedCurrency in currencies) {
    await db.insert('account_currencies', {
      'account_id': id,
      'currency': supportedCurrency,
      'is_primary': supportedCurrency == currency ? 1 : 0,
    });
  }
  return id;
}
