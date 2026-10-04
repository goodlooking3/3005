import 'package:flutter_test/flutter_test.dart';

import 'package:wasel/core/user_facing_errors.dart';

void main() {
  test('keeps a safe business message', () {
    expect(
      userFacingError(StateError('تعذر تحديث المخزون'), fallback: 'بديل'),
      'تعذر تحديث المخزون',
    );
  });

  test('removes technical state details', () {
    expect(
      userFacingError(StateError('Bad state: internal database failure'), fallback: 'رسالة آمنة'),
      'رسالة آمنة',
    );
  });

  test('keeps an argument validation message', () {
    expect(
      userFacingError(ArgumentError('سلة المشتريات فارغة'), fallback: 'بديل'),
      'سلة المشتريات فارغة',
    );
  });
}
