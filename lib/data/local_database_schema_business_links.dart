part of 'local_database_schema.dart';

Future<void> _ensureBusinessPartyLinks(Database db) async {
  const linkTables = [
    'marketplace_vendors',
    'purchase_orders',
    'sales_invoices',
    'sales_return_lines',
  ];
  final tableRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final existingTables = tableRows.map((row) => row['name'] as String).toSet();

  Future<Set<String>> columns(String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  final columnsByTable = <String, Set<String>>{};
  for (final table in linkTables) {
    if (!existingTables.contains(table)) continue;
    await _addColumnIfMissing(
      db,
      table,
      'party_id',
      'INTEGER REFERENCES parties(id)',
    );
    columnsByTable[table] = await columns(table);
  }
  final partiesColumns = existingTables.contains('parties')
      ? await columns('parties')
      : <String>{};
  final partiesReady =
      partiesColumns.containsAll({'id', 'name', 'type', 'active'});

  final vendorColumns = columnsByTable['marketplace_vendors'] ?? <String>{};
  final orderColumns = columnsByTable['purchase_orders'] ?? <String>{};
  final invoiceColumns = columnsByTable['sales_invoices'] ?? <String>{};
  final returnColumns = columnsByTable['sales_return_lines'] ?? <String>{};

  if (vendorColumns.contains('party_id')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_marketplace_vendors_party ON marketplace_vendors(party_id)',
    );
  }
  if (orderColumns.contains('party_id')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_orders_party ON purchase_orders(party_id)',
    );
  }
  if (invoiceColumns.contains('party_id')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_invoices_party ON sales_invoices(party_id)',
    );
  }

  if (partiesReady && vendorColumns.containsAll({'party_id', 'name'})) {
    await db.execute('''
      UPDATE marketplace_vendors AS vendor
      SET party_id = (
        SELECT party.id FROM parties party
        WHERE party.type = 'supplier' AND party.active = 1
          AND lower(trim(party.name)) = lower(trim(vendor.name))
        LIMIT 1
      )
      WHERE vendor.party_id IS NULL
        AND 1 = (
          SELECT COUNT(*) FROM parties party
          WHERE party.type = 'supplier' AND party.active = 1
            AND lower(trim(party.name)) = lower(trim(vendor.name))
        )
    ''');
  }
  if (partiesReady &&
      invoiceColumns.containsAll({'party_id', 'customer_name'})) {
    await db.execute('''
      UPDATE sales_invoices AS invoice
      SET party_id = (
        SELECT party.id FROM parties party
        WHERE party.type = 'customer' AND party.active = 1
          AND lower(trim(party.name)) = lower(trim(invoice.customer_name))
        LIMIT 1
      )
      WHERE invoice.party_id IS NULL
        AND 1 = (
          SELECT COUNT(*) FROM parties party
          WHERE party.type = 'customer' AND party.active = 1
            AND lower(trim(party.name)) = lower(trim(invoice.customer_name))
        )
    ''');
  }
  if (orderColumns.containsAll({'party_id', 'vendor_id'}) &&
      vendorColumns.containsAll({'party_id', 'id'})) {
    await db.execute('''
      UPDATE purchase_orders AS order_row
      SET party_id = (
        SELECT vendor.party_id FROM marketplace_vendors vendor
        WHERE vendor.id = order_row.vendor_id
      )
      WHERE order_row.party_id IS NULL AND order_row.vendor_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM marketplace_vendors vendor
          WHERE vendor.id = order_row.vendor_id AND vendor.party_id IS NOT NULL
        )
    ''');
  }
  if (partiesReady && orderColumns.containsAll({'party_id', 'vendor_name'})) {
    await db.execute('''
      UPDATE purchase_orders AS order_row
      SET party_id = (
        SELECT party.id FROM parties party
        WHERE party.type = 'supplier' AND party.active = 1
          AND lower(trim(party.name)) = lower(trim(order_row.vendor_name))
        LIMIT 1
      )
      WHERE order_row.party_id IS NULL
        AND 1 = (
          SELECT COUNT(*) FROM parties party
          WHERE party.type = 'supplier' AND party.active = 1
            AND lower(trim(party.name)) = lower(trim(order_row.vendor_name))
        )
    ''');
  }
  if (returnColumns.containsAll({'party_id', 'invoice_number'}) &&
      invoiceColumns.containsAll({'party_id', 'number'})) {
    await db.execute('''
      UPDATE sales_return_lines AS return_line
      SET party_id = (
        SELECT invoice.party_id FROM sales_invoices invoice
        WHERE invoice.number = return_line.invoice_number
      )
      WHERE return_line.party_id IS NULL
    ''');
  }
}
