import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/data/local_database_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() => LocalDatabase.instance.resetForTests());

  test('v23 upgrade adds nullable cost journal links without losing rows',
      () async {
    final db = await LocalDatabase.instance.database;
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('DROP TABLE sales_return_lines');
    await db.execute('DROP TABLE sales_invoices');
    await db.execute(
      'CREATE TABLE sales_invoices (id INTEGER PRIMARY KEY, number TEXT NOT NULL UNIQUE)',
    );
    await db.execute(
      'CREATE TABLE sales_return_lines (id INTEGER PRIMARY KEY, invoice_number TEXT NOT NULL)',
    );
    await db.insert('sales_invoices', {'number': 'LEGACY-SALE-1'});
    await db.insert(
      'sales_return_lines',
      {'invoice_number': 'LEGACY-SALE-1'},
    );

    await LocalDatabaseSchema.upgrade(db, 23);

    final invoiceColumns =
        await db.rawQuery('PRAGMA table_info(sales_invoices)');
    final returnColumns =
        await db.rawQuery('PRAGMA table_info(sales_return_lines)');
    expect(
      invoiceColumns.map((column) => column['name']),
      contains('cost_journal_entry_id'),
    );
    expect(
      returnColumns.map((column) => column['name']),
      contains('cost_journal_entry_id'),
    );
    expect(
      (await db.query('sales_invoices')).single['number'],
      'LEGACY-SALE-1',
    );
    expect(
      (await db.query('sales_return_lines')).single['invoice_number'],
      'LEGACY-SALE-1',
    );
  });
}
