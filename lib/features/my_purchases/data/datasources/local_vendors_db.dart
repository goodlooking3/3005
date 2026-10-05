import 'package:sqflite/sqflite.dart';

import '../../../../data/local_database.dart';
import '../../domain/vendor_model.dart';

class LocalVendorsDb {
  Future<Database> get _db => LocalDatabase.instance.database;

  Future<List<Vendor>> vendors({String? category}) async {
    final rows = await (await _db).query(
      'marketplace_vendors',
      where: category == null || category == 'الكل'
          ? 'approved = 1'
          : 'approved = 1 AND category = ?',
      whereArgs: category == null || category == 'الكل' ? null : [category],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Vendor.fromMap).toList(growable: false);
  }

  Future<List<MarketplaceProduct>> products(int vendorId) async {
    final rows = await (await _db).query(
      'marketplace_products',
      where: 'vendor_id = ? AND available = 1',
      whereArgs: [vendorId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(MarketplaceProduct.fromMap).toList(growable: false);
  }

  Future<int> saveVendor(Vendor vendor) => LocalDatabase.instance.write(
        (db) async {
          final values = vendor.toMap()..remove('id');
          if (vendor.id != null) {
            final existing = await db.query(
              'marketplace_vendors',
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [vendor.id],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              final changed = await db.update(
                'marketplace_vendors',
                values,
                where: 'id = ?',
                whereArgs: [vendor.id],
              );
              if (changed != 1) throw StateError('تعذر تحديث بيانات المورد');
              return vendor.id!;
            }
          }
          return db.insert('marketplace_vendors', values);
        },
      );

  Future<void> linkVendorToParty({
    required int vendorId,
    required int partyId,
  }) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          final suppliers = await txn.query(
            'parties',
            columns: ['id'],
            where: "id = ? AND type = 'supplier' AND active = 1",
            whereArgs: [partyId],
            limit: 1,
          );
          if (suppliers.isEmpty) {
            throw StateError('يجب ربط المورد بطرف مورد نشط');
          }
          final changed = await txn.update(
            'marketplace_vendors',
            {'party_id': partyId},
            where: 'id = ?',
            whereArgs: [vendorId],
          );
          if (changed != 1) throw StateError('المورد غير موجود');
        });
      });

  Future<int> saveProduct(MarketplaceProduct product) =>
      LocalDatabase.instance.write(
        (db) => db.insert(
          'marketplace_products',
          product.toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      );

  Future<void> seedIfEmpty() async {
    final count = Sqflite.firstIntValue(
          await (await _db)
              .rawQuery('SELECT COUNT(*) FROM marketplace_vendors'),
        ) ??
        0;
    if (count > 0) return;
    for (final vendor in VendorSeedData.vendors) {
      final vendorId = await saveVendor(vendor);
      for (final product in ProductSeedData.products.where(
          (p) => p.vendorId == VendorSeedData.vendors.indexOf(vendor) + 1)) {
        await saveProduct(MarketplaceProduct(
          vendorId: vendorId,
          name: product.name,
          category: product.category,
          price: product.price,
          currency: product.currency,
        ));
      }
    }
  }
}
