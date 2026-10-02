import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credit note PDF contains a generated document payload', () async {
    final bytes = await ExportService.buildCreditNotePdf(
      invoiceNumber: 'INV-100',
      customerName: 'عميل اختبار',
      currency: 'SAR',
      date: DateTime.utc(2026, 9, 13),
      journalId: 77,
      total: 27,
      lines: const [
        CreditNoteLine(
            itemName: 'منتج', quantity: 1.5, unitPrice: 18, total: 27),
      ],
    );
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
