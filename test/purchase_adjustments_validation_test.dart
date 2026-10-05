import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/features/my_purchases/domain/vendor_model.dart';

void main() {
  test(
      'purchase adjustments reject invalid input instead of silently zeroing it',
      () {
    PurchaseAdjustments? parse({
      String shipping = '',
      String discount = '',
      String recoverableTax = '',
      String nonRecoverableTax = '',
      double subtotal = 100,
    }) =>
        PurchaseAdjustments.tryParse(
          shipping: shipping,
          discount: discount,
          recoverableTax: recoverableTax,
          nonRecoverableTax: nonRecoverableTax,
          subtotal: subtotal,
        );

    expect(parse(shipping: 'not-a-number'), isNull);
    expect(parse(shipping: '-1'), isNull);
    expect(parse(shipping: 'NaN'), isNull);
    expect(parse(discount: '101'), isNull);
    expect(parse(subtotal: 0), isNull);

    final valid = parse(
      shipping: '20',
      discount: '10',
      recoverableTax: '15',
      nonRecoverableTax: '5',
      subtotal: 200,
    );
    expect(valid?.shipping, 20);
    expect(valid?.discount, 10);
    expect(valid?.totalTax, 20);
  });
}
