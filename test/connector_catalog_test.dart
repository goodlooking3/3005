import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/connectors/connector_adapter.dart';
import 'package:wasel/features/connectors/application/connector_catalog.dart';

void main() {
  const catalog = ConnectorCatalog();

  test('catalog exposes the supported connector families', () {
    expect(
      catalog.items.map((item) => item.id),
      containsAll([
        'whatsapp_business',
        'sms',
        'messenger',
        'gmail',
        'google_drive',
        'google_calendar',
        'notion',
        'browser',
        'instagram',
        'webhook',
      ]),
    );
  });

  test('catalog exposes categories and featured additions', () {
    expect(catalog.categories, containsAll(['الكل', 'المراسلة', 'الإنتاجية', 'مخصص']));
    expect(catalog.items.where((item) => item.featured), isNotEmpty);
    expect(catalog.items.firstWhere((item) => item.id == 'webhook').requiresEndpoint, isTrue);
  });

  test('catalog maps connected ids without mutating its source items', () {
    final connected = catalog.statusFor('webhook', {'webhook'});
    final disconnected = catalog.statusFor('sms', {'webhook'});

    expect(connected, ConnectorStatus.connected);
    expect(disconnected, ConnectorStatus.disconnected);
    expect(catalog.items.first.status, ConnectorStatus.disconnected);
  });
}
