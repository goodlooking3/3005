import 'connector_adapter.dart';

class ConnectorConfig {
  final String endpoint;
  final String displayName;
  const ConnectorConfig({required this.endpoint, required this.displayName});
}

class WebhookConnector implements ConnectorAdapter {
  final ConnectorConfig config;
  ConnectorStatus _status = ConnectorStatus.disconnected;
  WebhookConnector(this.config);
  @override
  String get id => 'webhook';
  @override
  String get displayName => config.displayName;
  @override
  ConnectorStatus get status => _status;
  @override
  Future<void> connect() async {
    if (!config.endpoint.startsWith('https://')) {
      throw ArgumentError('Webhook must use HTTPS');
    }
    _status = ConnectorStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    _status = ConnectorStatus.disconnected;
  }

  @override
  Future<void> testConnection() async {
    if (_status != ConnectorStatus.connected) {
      throw StateError('Connect the webhook first');
    }
  }
}

class OfficialMessagingConnector implements ConnectorAdapter {
  @override
  final String id;
  @override
  final String displayName;
  final String platform;
  ConnectorStatus _status = ConnectorStatus.disconnected;
  OfficialMessagingConnector({
    required this.id,
    required this.displayName,
    required this.platform,
  });
  @override
  ConnectorStatus get status => _status;
  @override
  Future<void> connect() async {
    _status = ConnectorStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    _status = ConnectorStatus.disconnected;
  }

  @override
  Future<void> testConnection() async {
    if (_status != ConnectorStatus.connected) {
      throw StateError('Connector is not connected');
    }
  }
}
