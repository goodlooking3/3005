import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/currency_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_purchases/data/purchase_engine.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';
import 'package:wasel/features/my_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_transaction.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await LocalDatabase.instance.resetForTests();
    await (await LocalDatabase.instance.database).insert('parties', {
      'id': 701,
      'name': 'مورد اختبار المشتريات',
      'type': 'supplier',
      'currency': 'SAR',
    });
  });

  test('purchase checkout receives the same product into unified inventory',
      () async {
    final product = MarketplaceProduct(
      vendorId: 1,
      name: 'صنف شراء تكاملي',
      category: 'تجزئة',
      price: 12,
      currency: 'SAR',
    );
    final receipt = await PurchaseEngine().checkout(
      vendor: const Vendor(
        partyId: 701,
        name: 'مورد تكاملي',
        category: 'تجزئة',
      ),
      cart: PurchaseCart([PurchaseCartLine(product: product, quantity: 3)]),
      walletName: 'المحفظة الرئيسية',
      walletAccount: 'المحفظة الرئيسية',
    );
    final db = await LocalDatabase.instance.database;
    final items = await db.query(
      'inventory_items',
      where: 'name = ?',
      whereArgs: [product.name],
    );
    final movements = await db.query(
      'inventory_movements',
      where: 'movement_type = ?',
      whereArgs: ['purchase_receipt'],
    );
    expect(items, hasLength(1));
    expect(items.single['quantity'], 3.0);
    expect(movements, hasLength(1));
    expect(movements.single['quantity'], 3.0);
    final order = (await db.query(
      'purchase_orders',
      where: 'number = ?',
      whereArgs: [receipt.order.number],
    ))
        .single;
    expect(order['party_id'], 701);
    final walletTransactions = await db.query(
      'wallet_transactions',
      where: 'related_entity_id = ?',
      whereArgs: [receipt.order.number],
    );
    expect(walletTransactions, hasLength(1));
    expect(walletTransactions.single['journal_entry_id'],
        order['journal_entry_id']);
  });

  test('purchase capitalization updates moving weighted average cost',
      () async {
    final engine = PurchaseEngine();
    final vendor = const Vendor(
      partyId: 701,
      name: 'مورد المتوسط',
      category: 'تجزئة',
    );
    final first = await engine.checkout(
      vendor: vendor,
      cart: PurchaseCart([
        PurchaseCartLine(
          product: const MarketplaceProduct(
            vendorId: 1,
            name: 'صنف متوسط مرجح',
            category: 'تجزئة',
            price: 10,
            currency: 'SAR',
          ),
          quantity: 2,
        ),
      ]),
      walletName: 'محفظة المتوسط',
      walletAccount: 'محفظة المتوسط',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final second = await engine.checkout(
      vendor: vendor,
      cart: PurchaseCart([
        PurchaseCartLine(
          product: const MarketplaceProduct(
            vendorId: 1,
            name: 'صنف متوسط مرجح',
            category: 'تجزئة',
            price: 20,
            currency: 'SAR',
          ),
          quantity: 3,
        ),
      ]),
      walletName: 'محفظة المتوسط',
      walletAccount: 'محفظة المتوسط',
    );

    final db = await LocalDatabase.instance.database;
    final item = (await db.query(
      'inventory_items',
      where: 'name = ?',
      whereArgs: ['صنف متوسط مرجح'],
    ))
        .single;
    expect(item['quantity'], 5.0);
    expect(item['cost_price'], 16.0);

    final order = (await db.query(
      'purchase_orders',
      where: 'number = ?',
      whereArgs: [second.order.number],
    ))
        .single;
    final inventoryAccount = (await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: ['1300'],
    ))
        .single;
    final journalLines = await db.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [order['journal_entry_id']],
      orderBy: 'id ASC',
    );
    final inventoryLine = journalLines.singleWhere(
      (line) => line['account_id'] == inventoryAccount['id'],
    );
    expect(inventoryLine['debit'], 60.0);
    expect(inventoryLine['credit'], 0.0);
    expect(first.order.number, isNot(second.order.number));
  });

  test('purchase adjustments capitalize shipping and discounts without tax',
      () async {
    const product = MarketplaceProduct(
        vendorId: 1,
        name: 'صنف تسويات',
        category: 'تجزئة',
        price: 100,
        currency: 'SAR');
    final receipt = await PurchaseEngine().checkout(
      vendor: const Vendor(
        partyId: 701,
        name: 'مورد التسويات',
        category: 'تجزئة',
      ),
      cart: const PurchaseCart(
        [PurchaseCartLine(product: product, quantity: 2)],
        adjustments: PurchaseAdjustments(shipping: 20, discount: 10),
      ),
      walletName: 'محفظة التسويات',
      walletAccount: 'محفظة التسويات',
    );
    final db = await LocalDatabase.instance.database;
    final item = (await db.query('inventory_items',
            where: 'name = ?', whereArgs: [product.name]))
        .single;
    expect(item['cost_price'], 105.0);
    final order = (await db.query('purchase_orders',
            where: 'number = ?', whereArgs: [receipt.order.number]))
        .single;
    expect(order['total'], 210.0);
    expect(order['recoverable_tax'], 0.0);
    expect((await db.query('accounts', where: 'code = ?', whereArgs: ['1410'])),
        isEmpty);
  });

  test('tax cannot be posted before a country policy is configured', () async {
    const product = MarketplaceProduct(
      vendorId: 1,
      name: 'صنف ضريبة غير مهيأة',
      category: 'تجزئة',
      price: 100,
      currency: 'SAR',
    );
    await expectLater(
      PurchaseEngine().checkout(
        vendor: const Vendor(
          partyId: 701,
          name: 'مورد اختبار المشتريات',
          category: 'تجزئة',
        ),
        cart: const PurchaseCart(
          [PurchaseCartLine(product: product)],
          adjustments: PurchaseAdjustments(recoverableTax: 15),
        ),
        walletName: 'المحفظة الرئيسية',
        walletAccount: 'المحفظة الرئيسية',
      ),
      throwsStateError,
    );
    final db = await LocalDatabase.instance.database;
    expect(await db.query('purchase_orders'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
  });

  test('currency repository requires and applies a dated exchange rate',
      () async {
    final repository = CurrencyRepository();
    await repository.saveRate(ExchangeRate(
      baseCurrency: 'USD',
      quoteCurrency: 'SAR',
      rate: 3.75,
      effectiveAt: DateTime.now().subtract(const Duration(minutes: 1)),
    ));
    expect(
      await repository.convert(amount: 10, from: 'USD', to: 'SAR'),
      37.5,
    );
    expect(
      () => repository.requireRate(baseCurrency: 'EUR', quoteCurrency: 'SAR'),
      throwsStateError,
    );
  });

  test('purchase rollback removes the journal when order persistence fails',
      () async {
    final product = MarketplaceProduct(
      vendorId: 999,
      name: 'صنف شراء فاشل ذرّيًا',
      category: 'تجزئة',
      price: 12,
      currency: 'SAR',
    );

    await expectLater(
      PurchaseEngine().checkout(
        vendor: const Vendor(
          id: 999,
          partyId: 701,
          name: 'مورد غير موجود',
          category: 'تجزئة',
        ),
        cart: PurchaseCart([PurchaseCartLine(product: product)]),
        walletName: 'محفظة الاختبار',
        walletAccount: 'محفظة الاختبار',
      ),
      throwsA(anything),
    );

    final db = await LocalDatabase.instance.database;
    expect(await db.query('purchase_orders'), isEmpty);
    expect(await db.query('purchase_order_lines'), isEmpty);
    expect(await db.query('wallet_transactions'), isEmpty);
    expect(await db.query('vouchers'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('accounts'), isEmpty);
  });

  test('wallet posting stores its transaction with the same journal entry',
      () async {
    final id = await WalletRepositoryImpl().saveTransaction(
      WalletTransaction(
        fromAccount: 'محفظة ذرية',
        toAccount: 'مورد ذري',
        type: WalletTransactionType.purchase,
        amount: 20,
        currency: 'SAR',
        note: 'اختبار ذرية المحفظة',
        date: DateTime(2026, 9, 22),
        reference: 'WALLET-ATOMIC-1',
      ),
    );
    final db = await LocalDatabase.instance.database;
    final transactions = await db.query('wallet_transactions');
    final journals = await db.query('journal_entries');
    expect(id, 1);
    expect(transactions, hasLength(1));
    expect(journals, hasLength(1));
    expect(transactions.single['journal_entry_id'], journals.single['id']);
    final debitLine = (await db.query(
      'journal_lines',
      where: 'journal_entry_id = ? AND debit > 0',
      whereArgs: [journals.single['id']],
    ))
        .single;
    final debitAccount = (await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [debitLine['account_id']],
    ))
        .single;
    expect(debitAccount['kind'], 'expense');
    expect(debitAccount['code'], isNot('1300'));
  });
}
