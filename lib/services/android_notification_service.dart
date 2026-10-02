import 'package:flutter/services.dart';

class AndroidNotificationEvent {
  final String packageName;
  final String title;
  final String body;
  final DateTime receivedAt;

  const AndroidNotificationEvent({
    required this.packageName,
    required this.title,
    required this.body,
    required this.receivedAt,
  });

  factory AndroidNotificationEvent.fromMap(Map<Object?, Object?> map) {
    return AndroidNotificationEvent(
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['receivedAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
    );
  }
}

class AndroidNotificationService {
  static const _events = EventChannel('wasel/android_notifications');
  static const _settings = MethodChannel('wasel/android_settings');

  Stream<AndroidNotificationEvent> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<Object?, Object?>>()
      .map(AndroidNotificationEvent.fromMap);

  Future<bool> openListenerSettings() async {
    try {
      return await _settings.invokeMethod<bool>('openNotificationListenerSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
