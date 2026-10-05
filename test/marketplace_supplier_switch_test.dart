import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/my_purchases/data/datasources/local_vendors_db.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';
import 'package:wasel/features/my_purchases/presentation/screens/marketplace_screen.dart';
import 'package:wasel/features/my_purchases/presentation/widgets/product_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  testWidgets('purchase search, cart review and checkout fit phone and desktop',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalVendorsDb();
    final firstVendorId = (await tester.runAsync(
      () => database.saveVendor(
        const Vendor(name: 'A Supplier', category: 'تجزئة'),
      ),
    ))!;
    final secondVendorId = (await tester.runAsync(
      () => database.saveVendor(
        const Vendor(name: 'B Supplier', category: 'تجزئة'),
      ),
    ))!;
    await tester.runAsync(
      () => database.saveProduct(
        MarketplaceProduct(
          vendorId: firstVendorId,
          name: 'المنتج الأول',
          category: 'تجزئة',
          price: 12,
        ),
      ),
    );
    await tester.runAsync(
      () => database.saveProduct(
        MarketplaceProduct(
          vendorId: secondVendorId,
          name: 'المنتج الثاني',
          category: 'تجزئة',
          price: 15,
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MarketplaceScreen())),
    );
    final firstProduct = find.text('المنتج الأول');
    for (var attempt = 0;
        attempt < 20 && firstProduct.evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(firstProduct, findsOneWidget);
    expect(tester.takeException(), isNull);
    final searchField =
        find.byKey(const ValueKey('marketplace-product-search'));
    await tester.enterText(searchField, 'لا يوجد تطابق');
    await tester.pump();
    expect(find.text('لا توجد منتجات تطابق البحث'), findsOneWidget);
    await tester.enterText(searchField, 'المنتج الأول');
    await tester.pump();
    expect(find.byType(ProductCard), findsOneWidget);
    await tester.tap(find.text('أضف للسلة').first);
    await tester.pump();
    expect(find.textContaining('السلة (1'), findsOneWidget);

    await tester.tap(find.text('B Supplier'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('تغيير المورد'), findsOneWidget);
    await tester.tap(find.text('إبقاء السلة'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('السلة (1'), findsOneWidget);

    await tester.tap(find.text('B Supplier'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('إفراغ وتغيير'));
    await tester.pump(const Duration(milliseconds: 300));
    final secondProduct = find.text('المنتج الثاني');
    for (var attempt = 0;
        attempt < 20 && secondProduct.evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('السلة (0'), findsOneWidget);
    expect(secondProduct, findsOneWidget);

    await tester.tap(find.text('أضف للسلة').first);
    await tester.pump();
    await tester.tap(find.textContaining('السلة (1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('مراجعة سلة الشراء'), findsOneWidget);
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pump();
    expect(find.textContaining('المجموع الفرعي: 30.00 SAR'), findsOneWidget);
    await tester.tap(find.text('متابعة للتسويات'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('تسويات الشراء'), findsOneWidget);
    expect(find.text('الإجمالي بعد التسويات: 30.00 SAR'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('تسويات الشراء'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إلغاء'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
