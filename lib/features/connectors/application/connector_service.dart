import '../../../core/connector_models.dart';
import '../../../core/production_config.dart';
import '../../../data/accounting_repository.dart';
import '../domain/connector_item.dart';

class ConnectorService {
  final AccountingRepository repository;

  const ConnectorService(this.repository);

  Future<void> saveSetup({
    required ConnectorItem connector,
    required String endpoint,
    required String qrPayload,
    required bool enabled,
    int? linkedAccountId,
  }) async {
    final normalizedEndpoint = endpoint.trim();
    if (ProductionConfig.localOnly && normalizedEndpoint.isNotEmpty) {
      throw const FormatException(
        'هذا الإصدار محلي بالكامل ولا يسمح بموصلات شبكية',
      );
    }
    if (normalizedEndpoint.isNotEmpty &&
        !normalizedEndpoint.startsWith('https://')) {
      throw const FormatException('يجب أن يبدأ Endpoint بـ HTTPS');
    }
    if (connector.id == 'bank_sandbox' && linkedAccountId == null) {
      throw const FormatException('اختر الحساب البنكي المحاسبي أولًا');
    }

    await repository.saveConnector(
      ConnectorSettings(
        provider: connector.id,
        displayName: connector.displayName,
        enabled: enabled,
        endpoint: normalizedEndpoint.isEmpty ? null : normalizedEndpoint,
        qrPayload: qrPayload.trim().isEmpty ? null : qrPayload.trim(),
        linkedAccountId: linkedAccountId,
      ),
    );
    await repository.log('update_connector', connector.displayName);
  }
}
