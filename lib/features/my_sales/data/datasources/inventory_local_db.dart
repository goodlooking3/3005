import 'package:sqflite/sqflite.dart';

import '../../../../data/local_database.dart';
import '../../domain/inventory_item.dart';

class InventoryLocalDb {
  Future<Database> get _db => LocalDatabase.instance.database;

  Future<List<InventoryItem>> items({bool activeOnly = true}) async {
    final rows = await (await _db).query(
      'inventory_items',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(InventoryItem.fromMap).toList(growable: false);
  }

  Future<int> save(InventoryItem item) => LocalDatabase.instance.write(
        (db) => db.insert(
          'inventory_items',
          item.toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      );

  Future<void> seedIfEmpty() async {
    final count = Sqflite.firstIntValue(
          await (await _db).rawQuery('SELECT COUNT(*) FROM inventory_items'),
        ) ??
        0;
    if (count > 0) return;
    for (final item in const [
      InventoryItem(name: 'مواد غذائية', sku: 'SKU-001', costPrice: 50, salePrice: 65, quantity: 12),
      InventoryItem(name: 'مياه معدنية', sku: 'SKU-002', costPrice: 10, salePrice: 18, quantity: 4),
    ]) {
      await save(item);
    }
  }
}
