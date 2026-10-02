enum ConnectorStatus { disconnected, connected, syncing, error }

abstract interface class ConnectorAdapter {
  String get id;
  String get displayName;
  ConnectorStatus get status;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> testConnection();
}

class ConnectorRegistry {
  final List<ConnectorAdapter> adapters;
  const ConnectorRegistry(this.adapters);
}
