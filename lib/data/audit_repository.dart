import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

/// Local audit writer; database triggers provide an atomic row-level trail.
class AuditRepository {
  AuditRepository._();

  static final instance = AuditRepository._();
  static final Random _secureRandom = Random.secure();

  Future<void> record({
    required String action,
    String entityType = 'application',
    String? entityId,
    String result = 'success',
    String details = '',
  }) =>
      LocalDatabase.instance.write(
        (db) => recordOn(
          db,
          action: action,
          entityType: entityType,
          entityId: entityId,
          result: result,
          details: details,
        ),
      );

  Future<void> recordOn(
    DatabaseExecutor db, {
    required String action,
    String entityType = 'application',
    String? entityId,
    String result = 'success',
    String details = '',
    String? actorId,
  }) async {
    final normalizedAction = action.trim();
    final normalizedEntityType = entityType.trim();
    final normalizedResult = result.trim();
    if (normalizedAction.isEmpty ||
        normalizedEntityType.isEmpty ||
        normalizedResult.isEmpty) {
      throw ArgumentError('Audit action, entity type, and result are required');
    }

    final context = await db.query(
      'audit_context',
      columns: ['actor_id', 'session_id'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    final current = context.isEmpty ? null : context.single;
    await db.insert('audit_log', {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'actor_id': actorId ?? current?['actor_id'] as String? ?? 'local-owner',
      'session_id': current?['session_id'],
      'entity_type': normalizedEntityType,
      'entity_id': entityId?.trim().isEmpty == true ? null : entityId?.trim(),
      'action': normalizedAction,
      'result': normalizedResult,
      'details': details,
    });
  }

  Future<String> beginLocalOwnerSession() async {
    final sessionId = List<int>.generate(
      32,
      (_) => _secureRandom.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await LocalDatabase.instance.write((db) async {
      await db.update(
        'audit_context',
        {'actor_id': 'local-owner', 'session_id': sessionId},
        where: 'id = ?',
        whereArgs: [1],
      );
    });
    return sessionId;
  }

  Future<void> endLocalOwnerSession() async {
    await LocalDatabase.instance.write((db) async {
      await db.update(
        'audit_context',
        {'actor_id': 'local-owner', 'session_id': null},
        where: 'id = ?',
        whereArgs: [1],
      );
    });
  }
}
