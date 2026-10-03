import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'dart:async';
import '../core/models.dart';
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
        version: 25,
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
    final next = _writeTail.then((_) async => operation(await database));
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
