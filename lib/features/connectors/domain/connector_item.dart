import '../../../connectors/connector_adapter.dart';

class ConnectorItem {
  final String id;
  final String displayName;
  final String description;
  final String category;
  final String actionLabel;
  final ConnectorStatus status;
  final bool featured;
  final bool requiresEndpoint;
  final bool supportsMessages;
  final bool implemented;

  const ConnectorItem({
    required this.id,
    required this.displayName,
    required this.description,
    this.category = 'أخرى',
    this.actionLabel = 'إعداد',
    this.status = ConnectorStatus.disconnected,
    this.featured = false,
    this.requiresEndpoint = false,
    this.supportsMessages = false,
    this.implemented = false,
  });

  ConnectorItem copyWith({ConnectorStatus? status}) => ConnectorItem(
        id: id,
        displayName: displayName,
        description: description,
        category: category,
        actionLabel: actionLabel,
        status: status ?? this.status,
        featured: featured,
        requiresEndpoint: requiresEndpoint,
        supportsMessages: supportsMessages,
        implemented: implemented,
      );
}

extension ConnectorStatusText on ConnectorStatus {
  String get arabicLabel => switch (this) {
        ConnectorStatus.connected => 'مفعّلة',
        ConnectorStatus.syncing => 'جارٍ التحديث',
        ConnectorStatus.error => 'تحتاج مراجعة',
        ConnectorStatus.disconnected => 'غير مفعّلة',
      };
}
