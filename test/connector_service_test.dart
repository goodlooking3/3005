import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/features/connectors/application/connector_service.dart';
import 'package:wasel/features/connectors/domain/connector_item.dart';

void main() {
  test('service rejects insecure endpoints before persistence', () async {
    const connector = ConnectorItem(
      id: 'webhook',
      displayName: 'Webhook مخصص',
      description: 'اختبار',
    );
    final service = ConnectorService(AccountingRepository());

    expect(
      () => service.saveSetup(
        connector: connector,
        endpoint: 'http://example.com',
        qrPayload: '',
        enabled: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
