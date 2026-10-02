import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_sales/data/sales_engine.dart';
import 'package:wasel/features/my_sales/domain/inventory_item.dart';

void main() {
  setUpAll(() {
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
  });

  test('sale and full return reconcile stock, movement log and journals',
      () async {
    final db = await LocalDatabase.instance.database;
    final alternateCashAccountId = await db.insert('accounts', {
      'code': 'TEST-CASH-ALT',
      'name': 'الصندوق البديل',
      'type': 'أصل',
      'kind': 'cash',
      'currency': 'SAR',
    });
    final alternateSalesAccountId = await db.insert('accounts', {
      'code': 'TEST-SALES-ALT',
      'name': 'إيرادات بديلة',
      'type': 'إيراد',
      'kind': 'revenue',
      'currency': 'SAR',
    });
    final number = 'MOV-RET-${DateTime.now().microsecondsSinceEpoch}';
    final itemId = await db.insert('inventory_items', {
      'name': 'صنف سجل مرتجع',
      'sku': number,
      'cost_price': 10.0,
      'sale_price': 18.0,
      'quantity': 5.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final invoice = SalesInvoice(
      number: number,
      customerName: 'عميل المرتجع',
      paymentAccount: 'الصندوق البديل',
      currency: 'SAR',
      issuedAt: DateTime.utc(2026, 1, 4),
      lines: [
        SalesInvoiceLine(
            itemId: itemId,
            itemName: 'صنف سجل مرتجع',
            quantity: 2,
            unitPrice: 18,
            unitCost: 10)
      ],
    );

    final engine = SalesEngine();
    final saleJournal = await engine.completeSale(
      invoice: invoice,
      cashAccountId: alternateCashAccountId,
      salesAccountId: alternateSalesAccountId,
    );
    expect(saleJournal, isPositive);
    expect(
        (await db
                .query('inventory_items', where: 'id = ?', whereArgs: [itemId]))
            .single['quantity'],
        3.0);

    final returnJournal = await engine.returnSale(
        invoiceNumber: number, returnedAt: DateTime.utc(2026, 1, 5));
    expect(returnJournal, isPositive);
    expect(
        (await db
                .query('inventory_items', where: 'id = ?', whereArgs: [itemId]))
            .single['quantity'],
        5.0);

    final invoiceRow = (await db
            .query('sales_invoices', where: 'number = ?', whereArgs: [number]))
        .single;
    expect(invoiceRow['status'], 'returned');
    expect(invoiceRow['reversal_journal_entry_id'], returnJournal);
    final movements = await engine.movements(itemId: itemId);
    expect(movements, hasLength(2));
    expect(movements.map((movement) => movement.quantity),
        containsAll(<double>[-2.0, 2.0]));
    expect(
        movements.every((movement) => movement.referenceId == number), isTrue);

    final journals = await db.query('journal_entries',
        where: 'number LIKE ?', whereArgs: ['RET-$number-%']);
    expect(journals, hasLength(1));
    expect(journals.every((row) => row['debit_total'] == row['credit_total']),
        isTrue);
    expect((await engine.summary())['sales'], 0.0);
  });

  test(
      'partial return updates only returned quantity and posts proportional reversal',
      () async {
    final db = await LocalDatabase.instance.database;
    final number = 'MOV-PARTIAL-${DateTime.now().microsecondsSinceEpoch}';
    final itemId = await db.insert('inventory_items', {
      'name': 'صنف مرتجع جزئي',
      'sku': number,
      'cost_price': 10.0,
      'sale_price': 18.0,
      'quantity': 10.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final invoice = SalesInvoice(
      number: number,
      customerName: 'عميل جزئي',
      paymentAccount: 'الصندوق',
      currency: 'SAR',
      issuedAt: DateTime.utc(2026, 1, 7),
      lines: [
        SalesInvoiceLine(
            itemId: itemId,
            itemName: 'صنف مرتجع جزئي',
            quantity: 4,
            unitPrice: 18,
            unitCost: 10)
      ],
    );
    final engine = SalesEngine();
    await engine.completeSale(
        invoice: invoice, cashAccountId: 101, salesAccountId: 401);
    final lineId = (await db.query('sales_invoice_lines',
            where: 'invoice_number = ?', whereArgs: [number]))
        .single['id'] as int;
    final reversalId = await engine.returnSale(
      invoiceNumber: number,
      cashAccountId: 101,
      salesAccountId: 401,
      quantitiesByLineId: {lineId: 1.5},
      returnedAt: DateTime.utc(2026, 1, 8),
    );
    expect(reversalId, isPositive);
    expect(
        (await db
                .query('inventory_items', where: 'id = ?', whereArgs: [itemId]))
            .single['quantity'],
        7.5);
    final invoiceRow = (await db
            .query('sales_invoices', where: 'number = ?', whereArgs: [number]))
        .single;
    expect(invoiceRow['status'], 'partially_returned');
    final returnRow = (await db.query('sales_return_lines',
            where: 'invoice_number = ?', whereArgs: [number]))
        .single;
    expect(returnRow['quantity'], 1.5);
    expect(returnRow['amount'], 27.0);
    final reversal = (await db
            .query('journal_entries', where: 'id = ?', whereArgs: [reversalId]))
        .single;
    expect(reversal['debit_total'], 27.0);
    expect(reversal['credit_total'], 27.0);
    final movements = await engine.movements(itemId: itemId);
    expect(movements.map((movement) => movement.quantity),
        containsAll(<double>[-4.0, 1.5]));
    final totals = await engine.summary();
    expect(totals['sales'], 45.0);
    expect(totals['costs'], 25.0);
    expect(totals['profit'], 20.0);
  });

  test('cancellation is idempotent and records a compensating movement',
      () async {
    final db = await LocalDatabase.instance.database;
    final number = 'MOV-CAN-${DateTime.now().microsecondsSinceEpoch}';
    final itemId = await db.insert('inventory_items', {
      'name': 'صنف سجل إلغاء',
      'sku': number,
      'cost_price': 4.0,
      'sale_price': 7.0,
      'quantity': 3.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final invoice = SalesInvoice(
      number: number,
      customerName: 'عميل الإلغاء',
      paymentAccount: 'الصندوق',
      currency: 'SAR',
      issuedAt: DateTime.utc(2026, 1, 6),
      lines: [
        SalesInvoiceLine(
            itemId: itemId,
            itemName: 'صنف سجل إلغاء',
            quantity: 1,
            unitPrice: 7,
            unitCost: 4)
      ],
    );
    final engine = SalesEngine();
    await engine.completeSale(
        invoice: invoice, cashAccountId: 101, salesAccountId: 401);
    await engine.cancelSale(invoiceNumber: number);
    await expectLater(
        () => engine.cancelSale(invoiceNumber: number), throwsStateError);
    expect(
        (await db
                .query('inventory_items', where: 'id = ?', whereArgs: [itemId]))
            .single['quantity'],
        3.0);
    expect(
        (await db.query('inventory_movements',
            where: 'reference_id = ?', whereArgs: [number])),
        hasLength(2));
  });

  test('multi-line returns can be completed across separate operations',
      () async {
    final db = await LocalDatabase.instance.database;
    final number = 'MOV-STAGED-${DateTime.now().microsecondsSinceEpoch}';
    final firstItemId = await db.insert('inventory_items', {
      'name': 'صنف مرتجع مرحلي 1',
      'sku': '$number-1',
      'cost_price': 5.0,
      'sale_price': 9.0,
      'quantity': 10.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final secondItemId = await db.insert('inventory_items', {
      'name': 'صنف مرتجع مرحلي 2',
      'sku': '$number-2',
      'cost_price': 8.0,
      'sale_price': 14.0,
      'quantity': 10.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final invoice = SalesInvoice(
      number: number,
      customerName: 'عميل المرتجع المرحلي',
      paymentAccount: 'الصندوق',
      currency: 'SAR',
      issuedAt: DateTime.utc(2026, 1, 9),
      lines: [
        SalesInvoiceLine(
            itemId: firstItemId,
            itemName: 'صنف مرتجع مرحلي 1',
            quantity: 2,
            unitPrice: 9,
            unitCost: 5),
        SalesInvoiceLine(
            itemId: secondItemId,
            itemName: 'صنف مرتجع مرحلي 2',
            quantity: 3,
            unitPrice: 14,
            unitCost: 8),
      ],
    );
    final engine = SalesEngine();
    await engine.completeSale(
        invoice: invoice, cashAccountId: 101, salesAccountId: 401);
    final lines = await db.query('sales_invoice_lines',
        where: 'invoice_number = ?', whereArgs: [number], orderBy: 'id ASC');
    await engine.returnSale(
      invoiceNumber: number,
      cashAccountId: 101,
      salesAccountId: 401,
      quantitiesByLineId: {lines[0]['id']! as int: 2},
      returnedAt: DateTime.utc(2026, 1, 10),
    );
    expect(
        (await db.query('sales_invoices',
                where: 'number = ?', whereArgs: [number]))
            .single['status'],
        'partially_returned');

    await engine.returnSale(
      invoiceNumber: number,
      cashAccountId: 101,
      salesAccountId: 401,
      quantitiesByLineId: {lines[1]['id']! as int: 1},
      returnedAt: DateTime.utc(2026, 1, 11),
    );
    expect(
        (await db.query('sales_invoices',
                where: 'number = ?', whereArgs: [number]))
            .single['status'],
        'partially_returned');
    expect(
        (await db.query('sales_return_lines',
            where: 'invoice_number = ?', whereArgs: [number])),
        hasLength(2));
    expect((await engine.summary())['sales'], greaterThan(0));

    await expectLater(
      () => engine.returnSale(
        invoiceNumber: number,
        cashAccountId: 101,
        salesAccountId: 401,
        quantitiesByLineId: {999999: 1},
      ),
      throwsStateError,
    );
  });
}
