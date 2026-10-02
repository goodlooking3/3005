import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/connector_models.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/features/connectors/application/message_accounting_service.dart';
import 'package:wasel/core/accounting.dart';

void main() {
  test('service rejects a message without a valid amount', () async {
    final service = MessageAccountingService(AccountingRepository());
    final message = IncomingMessage(
      provider: 'SMS',
      sender: 'اختبار',
      senderPhone: null,
      body: 'رسالة بلا مبلغ',
      receivedAt: DateTime(2026, 1, 1),
    );

    expect(
      () => service.postMessage(
        message: message,
        type: VoucherType.receipt,
        debitAccount: 'الصندوق الرئيسي',
        creditAccount: 'إيرادات الخدمات',
      ),
      throwsArgumentError,
    );
  });
}
