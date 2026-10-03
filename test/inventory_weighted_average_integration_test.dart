import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_purchases/data/purchase_engine.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';
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

  test('moving average and returns retain the original sale cost', () async {
    final db = await LocalDatabase.instance.database;
    final itemId = await db.insert('inventory_items', {
      'name': 'صنف متوسط ومرتجع تاريخي',
      'sku': 'AVG-RETURN',
      'cost_price': 10.0,
      'sale_price': 30.0,
      'quantity': 2.0,
      'low_stock_threshold': 1.0,
      'currency': 'SAR',
    });
    final purchaseEngine = PurchaseEngine();
    final vendor = const Vendor(name: 'مورد المتوسط', category: 'تجزئة');

    Future<void> purchase(double price, int quantity) async {
      await purchaseEngine.checkout(
        vendor: vendor,
        cart: PurchaseCart([
          PurchaseCartLine(
            product: MarketplaceProduct(
              vendorId: 1,
              inventoryItemId: itemId,
              name: 'صنف متوسط ومرتجع تاريخي',
              category: 'تجزئة',
              price: price,
              currency: 'SAR',
            ),
            quantity: quantity,
          ),
        ]),
        walletName: 'محفظة المتوسط',
        walletAccount: 'محفظة المتوسط',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    await purchase(20, 2);
    var item = (await db.query(
      'inventory_items',
      where: 'id = ?',
      whereArgs: [itemId],
    ))
        .single;
    expect(item['quantity'], 4.0);
    expect(item['cost_price'], 15.0);

    final number = 'AVG-RETURN-${DateTime.now().microsecondsSinceEpoch}';
    final sales = SalesEngine();
    await sales.completeSale(
      invoice: SalesInvoice(
        number: number,
        customerName: 'عميل اختبار المتوسط',
        paymentAccount: 'الصندوق',
        currency: 'SAR',
        issuedAt: DateTime.utc(2026, 2, 1),
        lines: [
          SalesInvoiceLine(
            itemId: itemId,
            itemName: 'صنف متوسط ومرتجع تاريخي',
            quantity: 2,
            unitPrice: 30,
            unitCost: 999,
          ),
        ],
      ),
      cashAccountId: 101,
      salesAccountId: 401,
    );
    final invoiceRow = (await db.query(
      'sales_invoices',
      where: 'number = ?',
      whereArgs: [number],
    ))
        .single;
    expect(invoiceRow['cost_of_goods_sold'], 30.0);

    await purchase(25, 2);
    item = (await db.query(
      'inventory_items',
      where: 'id = ?',
      whereArgs: [itemId],
    ))
        .single;
    expect(item['quantity'], 4.0);
    expect(item['cost_price'], 20.0);

    final lineId = (await db.query(
      'sales_invoice_lines',
      where: 'invoice_number = ?',
      whereArgs: [number],
    ))
        .single['id'] as int;
    await sales.returnSale(
      invoiceNumber: number,
      quantitiesByLineId: {lineId: 1},
      returnedAt: DateTime.utc(2026, 2, 2),
    );
    item = (await db.query(
      'inventory_items',
      where: 'id = ?',
      whereArgs: [itemId],
    ))
        .single;
    expect(item['quantity'], 5.0);
    expect(item['cost_price'], closeTo(19.0, 0.000001));

    final returnLine = (await db.query(
      'sales_return_lines',
      where: 'invoice_number = ?',
      whereArgs: [number],
    ))
        .single;
    final returnCost = (await db.query(
      'journal_entries',
      where: 'id = ?',
      whereArgs: [returnLine['cost_journal_entry_id']],
    ))
        .single;
    expect(returnCost['debit_total'], 15.0);
    expect(returnCost['credit_total'], 15.0);
  });
}
