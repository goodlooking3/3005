import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';
import 'package:wasel/features/my_sales/domain/inventory_item.dart';

void main() {
  test('purchase cart totals quantities and preserves currency', () {
    const product = MarketplaceProduct(
      vendorId: 1,
      name: 'منتج',
      category: 'تجزئة',
      price: 12.5,
      currency: 'SAR',
    );
    const cart = PurchaseCart([PurchaseCartLine(product: product, quantity: 3)]);
    expect(cart.total, 37.5);
    expect(cart.currency, 'SAR');
  });

  test('inventory item identifies low stock and profit', () {
    const item = InventoryItem(
      name: 'مياه',
      costPrice: 10,
      salePrice: 18,
      quantity: 4,
      lowStockThreshold: 5,
    );
    expect(item.lowStock, isTrue);
    expect(item.unitProfit, 8);
  });

  test('sales invoice calculates revenue, cost, and profit', () {
    final invoice = SalesInvoice(
      number: 'S-1',
      customerName: 'عميل',
      paymentAccount: 'الصندوق',
      currency: 'SAR',
      issuedAt: DateTime(2026, 1, 1),
      lines: [
        SalesInvoiceLine(itemId: 1, itemName: 'مياه', quantity: 2, unitPrice: 18, unitCost: 10),
      ],
    );
    expect(invoice.total, 36);
    expect(invoice.costOfGoodsSold, 20);
    expect(invoice.profit, 16);
  });
}
