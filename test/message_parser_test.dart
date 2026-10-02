import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/models.dart';

void main() {
  test('extracts Arabic amount, currency and reference', () {
    final result = MessageParser.parse(
        'تم استلام حوالة بمبلغ 185,000 ريال يمني. رقم الحوالة 8492317');
    expect(result.amount, 185000);
    expect(result.currency, 'ريال');
    expect(result.reference, '8492317');
  });

  test('extracts USD amount and reference', () {
    final result = MessageParser.parse('تم تحويل مبلغ \$420، رقم السند 773102');
    expect(result.amount, 420);
    expect(result.currency, r'$');
    expect(result.reference, '773102');
  });
}
