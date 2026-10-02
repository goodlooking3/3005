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

  setUp(() => LocalDatabase.instance.resetForTests());

  test('purchase checkout receives the same product into unified inventory',
      () async {
    final product = MarketplaceProduct(
      vendorId: 1,
      name: 'صنف شراء تكاملي',
      category: 'تجزئة',
      price: 12,
      currency: 'SAR',
    );
    await PurchaseEngine().checkout(
      vendor: const Vendor(name: 'مورد تكاملي', category: 'تجزئة'),
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
  });
}
