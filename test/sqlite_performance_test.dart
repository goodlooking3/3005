import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('SQLite bulk writes and indexed reads stay within the local budget',
      () async {
    final db = await LocalDatabase.instance.database;
    await db.execute(
        'CREATE TEMP TABLE records (id INTEGER PRIMARY KEY, reference TEXT NOT NULL, body TEXT NOT NULL)');
    await db
        .execute('CREATE INDEX idx_records_reference ON records(reference)');
    addTearDown(() => db.execute('DROP TABLE IF EXISTS records'));

    final stopwatch = Stopwatch()..start();
    await db.transaction((txn) async {
      for (var i = 0; i < 3000; i++) {
        await txn.insert('records', {
          'id': i + 1,
          'reference': 'REF-${i % 100}',
          'body': 'حركة محلية رقم $i محفوظة للعمل دون اتصال ' * 3,
        });
      }
    });
    final rows = await db
        .query('records', where: 'reference = ?', whereArgs: ['REF-42']);
    stopwatch.stop();

    expect(rows, hasLength(30));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM records WHERE reference = ?',
        ['REF-42']);
    expect(plan.join(' '), contains('idx_records_reference'));
  });

  test('sync payload compression reduces repetitive local data size', () {
    final payload = jsonEncode({
      'schema': 1,
      'items': List.generate(
          1000,
          (i) => {
                'entity': 'remittance',
                'operation': 'upsert',
                'reference': 'LOCAL-REFERENCE-${i % 20}',
                'body': 'بيانات محلية قابلة للمزامنة بعد عودة الاتصال' * 4,
              }),
    });
    final compressed = gzip.encode(utf8.encode(payload));
    expect(compressed.length,
        lessThan(Uint8List.fromList(utf8.encode(payload)).length));
  });
}
