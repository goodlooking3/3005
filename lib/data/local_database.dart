import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'dart:async';
import '../core/models.dart';
import 'accounting_authorization.dart';
import 'local_database_schema.dart';
import 'database_factory_web.dart'
    if (dart.library.io) 'database_factory_default.dart' as platform_database;

class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();
  String? _databaseDirectoryForTests;
  Database? _db;
  Future<Database>? _opening;
  Future<void> _writeTail = Future<void>.value();

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!;
    final opening = _openDatabase();
    _opening = opening;
    try {
      return await opening;
    } finally {
      _opening = null;
    }
  }

  @visibleForTesting
  void setDatabaseDirectoryForTests(String directory) {
    _databaseDirectoryForTests = directory;
  }

  @visibleForTesting
  Future<Database> openVersionedDatabaseForTests({
    required String directory,
    required int version,
    required Future<void> Function(Database db, int version) onCreate,
  }) =>
      databaseFactory.openDatabase(
        p.join(directory, 'wasel.db'),
        options: OpenDatabaseOptions(version: version, onCreate: onCreate),
      );

  Future<Database> _openDatabase() async {
    platform_database.configureDatabaseFactoryForPlatform();
    final factory = databaseFactory;
    final path = _databaseDirectoryForTests != null
        ? p.join(_databaseDirectoryForTests!, 'wasel.db')
        : kIsWeb
            ? 'wasel.db'
            : p.join(await factory.getDatabasesPath(), 'wasel.db');
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 32,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          if (!kIsWeb) {
            await db.execute('PRAGMA journal_mode = WAL');
            await db.execute('PRAGMA synchronous = NORMAL');
            await db.execute('PRAGMA temp_store = MEMORY');
            await db.execute('PRAGMA cache_size = -8000');
          }
        },
        onCreate: (db, _) => LocalDatabaseSchema.createInitialSchema(db),
        onUpgrade: (db, oldVersion, _) =>
            LocalDatabaseSchema.upgrade(db, oldVersion),
      ),
    );
    return _db!;
  }

  Future<int> insert(Remittance item) =>
      write((db) => db.insert('remittances', item.toMap()));
  Future<T> write<T>(Future<T> Function(Database db) operation) {
    final next = _writeTail.then((_) async {
      final db = await database;
      try {
        return await operation(db);
      } catch (error) {
        try {
          final denied = error is AuthorizationDeniedException ? error : null;
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
            'actor_id': current?['actor_id'] ?? 'local-owner',
            'session_id': current?['session_id'],
            'entity_type': denied == null ? 'application' : 'permission',
            'entity_id': denied?.permission.name,
            'action': denied == null ? 'db.write' : 'authorization.denied',
            'result': 'failure',
            'details': denied != null
                ? 'role=${denied.role}; required=${denied.permission.name}'
                : 'operation failed (${error.runtimeType})',
          });
        } catch (_) {
          // Preserve the original write failure if the audit sink is unavailable.
        }
        rethrow;
      }
    });
    _writeTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  @visibleForTesting
  Future<void> waitForPendingWrites() => _writeTail;

  /// Clears the local database for deterministic tests.
  /// Production code must never call this method.
  Future<void> resetForTests() async {
    await _writeTail;
    final path = _databaseDirectoryForTests != null
        ? p.join(_databaseDirectoryForTests!, 'wasel.db')
        : p.join(await getDatabasesPath(), 'wasel.db');
    final db = _db;
    _db = null;
    _opening = null;
    _writeTail = Future<void>.value();
    await db?.close();
    await deleteDatabase(path);
  }

  Future<List<Remittance>> all() async {
    final rows = await (await database).query(
      'remittances',
      orderBy: 'created_at DESC',
    );
    return rows.map(Remittance.fromMap).toList();
  }
}
