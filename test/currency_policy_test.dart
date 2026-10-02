import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/currency_policy.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/data/currency_repository.dart';
import 'package:wasel/features/my_purchases/data/purchase_engine.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  test('values a foreign amount in the company base currency', () async {
    final repository = CurrencyRepository();
    await repository.saveRate(ExchangeRate(
      baseCurrency: 'USD',
      quoteCurrency: 'SAR',
      rate: 3.75,
      effectiveAt: DateTime(2026, 9, 22),
    ));
    final valuation = await currencyPolicy.value(
      db: await LocalDatabase.instance.database,
      amount: 10,
      currency: 'USD',
      at: DateTime(2026, 9, 22, 1),
    );
    expect(valuation.currency, 'USD');
    expect(valuation.baseCurrency, 'SAR');
    expect(valuation.exchangeRate, 3.75);
    expect(valuation.baseAmount, 37.5);
  });

  test('calculates a signed realized exchange difference', () {
    final difference = currencyPolicy.difference(
      bookedBaseAmount: 37.5,
      settledBaseAmount: 38.0,
    );
    expect(difference.difference, 0.5);
    expect(difference.isGain, isTrue);
    expect(difference.isLoss, isFalse);
  });

  test('rejects a purchase cart containing different currencies', () async {
    const sar = MarketplaceProduct(
      vendorId: 1,
      name: 'منتج ريال',
      category: 'تجزئة',
      price: 10,
      currency: 'SAR',
    );
    const usd = MarketplaceProduct(
      vendorId: 1,
      name: 'منتج دولار',
      category: 'تجزئة',
      price: 10,
      currency: 'USD',
    );
    await expectLater(
      PurchaseEngine().checkout(
        vendor: const Vendor(name: 'مورد', category: 'تجزئة'),
        cart: const PurchaseCart([
          PurchaseCartLine(product: sar),
          PurchaseCartLine(product: usd),
        ]),
        walletName: 'محفظة',
        walletAccount: 'محفظة',
      ),
      throwsStateError,
    );
  });
}
