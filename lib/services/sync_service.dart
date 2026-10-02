import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/production_config.dart';
import '../data/accounting_repository.dart';

class SyncResult {
  final int uploaded;
  final int remaining;
  const SyncResult({required this.uploaded, required this.remaining});
}

enum ConflictResolution { keepLocal, keepRemote, manualReview }

class ConflictPolicy {
  const ConflictPolicy();
  ConflictResolution resolve(
      {required DateTime localUpdatedAt,
      required DateTime remoteUpdatedAt,
      required bool remoteDeleted}) {
    if (remoteDeleted && localUpdatedAt.isAfter(remoteUpdatedAt)) {
      return ConflictResolution.manualReview;
    }
    if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
      return ConflictResolution.keepLocal;
    }
    if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
      return ConflictResolution.keepRemote;
    }
    return ConflictResolution.manualReview;
  }
}

class SyncService {
  final AccountingRepository repository;
  final http.Client client;
  const SyncService({required this.repository, required this.client});

  Future<SyncResult> pushPending(
      {required Uri endpoint, required String bearerToken}) async {
    if (endpoint.scheme != 'https') {
      throw ArgumentError('Sync endpoint must use HTTPS');
    }
    if (bearerToken.trim().isEmpty) {
      throw ArgumentError('Sync bearer token is required');
    }
    if (ProductionConfig.localOnly) {
      throw StateError('المزامنة الخارجية معطلة في الوضع المحلي');
    }
    final queue = await repository.pendingSyncEnvelope();
    final pending = queue.length;
    if (pending == 0) return const SyncResult(uploaded: 0, remaining: 0);
    final response = await client.post(endpoint,
        headers: {
          'authorization': 'Bearer $bearerToken',
          'content-type': 'application/json'
        },
        body: jsonEncode({'schema': 1, 'items': queue}));
    if (response.statusCode == 409) {
      for (final item in queue) {
        await repository.recordConflict(
            entity: item['entity']! as String,
            entityId: item['entity_id']! as int,
            localHash: item['idempotency_key']! as String,
            remoteHash: 'conflict');
      }
      throw StateError('Sync conflict requires review');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Sync failed with HTTP ${response.statusCode}');
    }
    await repository.markSynced(queue.map((item) => item['id']! as int));
    return SyncResult(
      uploaded: pending,
      remaining: await repository.pendingSyncCount(),
    );
  }

  /// Keeps the local queue durable while offline and retries automatically.
  /// A failed request is treated as a temporary connectivity failure; data is
  /// never removed from SQLite until the server acknowledges the batch.
  AutoSyncScheduler startAutomaticRetry({
    required Uri endpoint,
    required String bearerToken,
    Duration interval = const Duration(seconds: 30),
    void Function(SyncResult result)? onSynced,
    void Function(Object error)? onTemporaryFailure,
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError('Sync retry interval must be positive');
    }
    final scheduler = AutoSyncScheduler(
      sync: () => pushPending(endpoint: endpoint, bearerToken: bearerToken),
      interval: interval,
      onSynced: onSynced,
      onTemporaryFailure: onTemporaryFailure,
    );
    scheduler.start();
    return scheduler;
  }
}

class AutoSyncScheduler {
  final Future<SyncResult> Function() sync;
  final Duration interval;
  final void Function(SyncResult result)? onSynced;
  final void Function(Object error)? onTemporaryFailure;
  Timer? _timer;
  bool _running = false;

  AutoSyncScheduler({
    required this.sync,
    required this.interval,
    this.onSynced,
    this.onTemporaryFailure,
  });

  void start() {
    _timer ??= Timer.periodic(interval, (_) => _attempt());
    unawaited(_attempt());
  }

  Future<void> _attempt() async {
    if (_running) return;
    _running = true;
    try {
      final result = await sync();
      if (result.uploaded > 0) onSynced?.call(result);
    } catch (error) {
      // Keep the queue intact and retry on the next tick when connectivity
      // returns. The callback may update a small offline/online indicator.
      onTemporaryFailure?.call(error);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
