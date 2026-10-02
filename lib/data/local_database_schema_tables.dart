part of 'local_database_schema.dart';

Future<void> _createCoreTables(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS remittances (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, sender TEXT NOT NULL, phone TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, reference TEXT NOT NULL, message TEXT NOT NULL, source TEXT NOT NULL, type TEXT NOT NULL)''',
  );
  await _createAccountingTables(db);
}

Future<void> _createAccountingTables(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS vouchers (id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL, type TEXT NOT NULL, description TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, base_amount REAL, base_currency TEXT, exchange_rate REAL, date TEXT NOT NULL, recipient_name TEXT, payer_name TEXT, debit_account_id INTEGER, credit_account_id INTEGER)''',
  );
  await _addColumnIfMissing(db, 'vouchers', 'recipient_name', 'TEXT');
  await _addColumnIfMissing(db, 'vouchers', 'payer_name', 'TEXT');
  await _addColumnIfMissing(db, 'vouchers', 'debit_account_id', 'INTEGER');
  await _addColumnIfMissing(db, 'vouchers', 'credit_account_id', 'INTEGER');
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, action TEXT NOT NULL, details TEXT NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, entity_id INTEGER NOT NULL, operation TEXT NOT NULL, created_at TEXT NOT NULL, synced INTEGER NOT NULL DEFAULT 0, idempotency_key TEXT NOT NULL DEFAULT '', remote_version INTEGER NOT NULL DEFAULT 0)''',
  );
}

Future<void> _createEnterpriseTables(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, type TEXT NOT NULL, kind TEXT NOT NULL, parent_id INTEGER, is_group INTEGER NOT NULL DEFAULT 0, currency TEXT NOT NULL DEFAULT 'SAR', opening_balance REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS voucher_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, voucher_id INTEGER NOT NULL, account_id INTEGER, account_name TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, currency TEXT NOT NULL DEFAULT 'SAR', base_debit REAL, base_credit REAL, party_name TEXT, FOREIGN KEY(voucher_id) REFERENCES vouchers(id))''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS parties (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL, phone TEXT, email TEXT, currency TEXT NOT NULL DEFAULT 'SAR', active INTEGER NOT NULL DEFAULT 1)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS company_profile (id INTEGER PRIMARY KEY CHECK(id = 1), name TEXT NOT NULL, legal_name TEXT, tax_number TEXT, phone TEXT, email TEXT, address TEXT, base_currency TEXT NOT NULL DEFAULT 'SAR')''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS user_profile (id INTEGER PRIMARY KEY CHECK(id = 1), display_name TEXT NOT NULL, email TEXT, phone TEXT, role TEXT NOT NULL DEFAULT 'admin')''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS connector_configs (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 0, endpoint TEXT, qr_payload TEXT, updated_at TEXT NOT NULL)''',
  );
  await _addColumnIfMissing(
      db, 'connector_configs', 'linked_account_id', 'INTEGER');
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS incoming_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL, sender TEXT NOT NULL, sender_phone TEXT, body TEXT NOT NULL, received_at TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0, parsed_amount REAL, parsed_currency TEXT, reference TEXT)''',
  );
  await _createJournalTable(db);
  await _createAccountCurrenciesTable(db);
  await _createWalletTables(db);
  await _createCommerceTables(db);
  await _createCurrencyTables(db);
  await _createBankSandboxTable(db);
  await _createWalletIntegrityIndexes(db);
}

Future<void> _createWalletIntegrityIndexes(Database db) async {
  await db.execute(
      'DELETE FROM wallet_accounts WHERE id NOT IN (SELECT MIN(id) FROM wallet_accounts GROUP BY wallet_id, name, currency)');
  await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_account_identity ON wallet_accounts(wallet_id, name, currency)');
}

Future<void> _addWalletAccountReferenceColumns(Database db) async {
  await _addColumnIfMissing(
      db, 'wallet_transactions', 'from_wallet_account_id', 'INTEGER');
  await _addColumnIfMissing(
      db, 'wallet_transactions', 'to_wallet_account_id', 'INTEGER');
}

Future<void> _addWalletAccountMetadata(Database db) async {
  for (final column in [
    ('external_type', 'TEXT'),
    ('external_id', 'TEXT'),
    ('connection_status', "TEXT NOT NULL DEFAULT 'not_connected'"),
    ('balance_source', "TEXT NOT NULL DEFAULT 'manual'"),
    ('last_synced_at', 'TEXT'),
    ('last_error', 'TEXT'),
  ]) {
    await _addColumnIfMissing(db, 'wallet_accounts', column.$1, column.$2);
  }
}

Future<void> _createBankSandboxTable(Database db) => db.execute(
    "CREATE TABLE IF NOT EXISTS bank_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL, external_id TEXT NOT NULL, linked_account_id INTEGER NOT NULL, amount REAL NOT NULL CHECK(amount > 0), currency TEXT NOT NULL, direction TEXT NOT NULL CHECK(direction IN ('credit', 'debit')), booked_at TEXT NOT NULL, description TEXT NOT NULL, imported_at TEXT NOT NULL, posted_voucher_id INTEGER, status TEXT NOT NULL DEFAULT 'imported', UNIQUE(provider, external_id))");
Future<void> _createCurrencyTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS currencies (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
  await db.execute('''
      CREATE TABLE IF NOT EXISTS exchange_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base_currency TEXT NOT NULL,
        quote_currency TEXT NOT NULL,
        rate REAL NOT NULL CHECK(rate > 0),
        effective_at TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        UNIQUE(base_currency, quote_currency, effective_at)
      )
    ''');
  final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM currencies'),
      ) ??
      0;
  if (count == 0) {
    for (final currency in const [
      ['SAR', 'ريال سعودي', 'ر.س'],
      ['USD', 'دولار أمريكي', r'$'],
      ['EUR', 'يورو', '€'],
      ['YER', 'ريال يمني', 'ر.ي'],
    ]) {
      await db.insert('currencies', {
        'code': currency[0],
        'name': currency[1],
        'symbol': currency[2],
      });
    }
  }
}

Future<void> _createWalletTables(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS wallets (id TEXT PRIMARY KEY, name TEXT NOT NULL, provider_id TEXT NOT NULL, provider_name TEXT NOT NULL, deep_link TEXT)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS wallet_accounts (id INTEGER PRIMARY KEY AUTOINCREMENT, wallet_id TEXT NOT NULL, name TEXT NOT NULL, currency TEXT NOT NULL, balance REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, account_id INTEGER, external_type TEXT, external_id TEXT, connection_status TEXT NOT NULL DEFAULT 'not_connected', balance_source TEXT NOT NULL DEFAULT 'manual', last_synced_at TEXT, last_error TEXT, FOREIGN KEY(wallet_id) REFERENCES wallets(id))''',
  );
  await _addWalletAccountMetadata(db);
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS wallet_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, from_account TEXT NOT NULL, to_account TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, base_amount REAL, base_currency TEXT, exchange_rate REAL, fee_amount REAL, fee_currency TEXT, note TEXT NOT NULL DEFAULT '', date TEXT NOT NULL, reference TEXT, source_reference TEXT, raw_payload TEXT, related_module TEXT, related_entity_id TEXT, journal_entry_id INTEGER, status TEXT NOT NULL DEFAULT 'posted', FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id))''',
  );
  await _addWalletAccountReferenceColumns(db);
  await _addWalletOperationMetadata(db);
}

Future<void> _createCommerceTables(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS marketplace_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '', image_url TEXT, approved INTEGER NOT NULL DEFAULT 1)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS marketplace_products (id INTEGER PRIMARY KEY AUTOINCREMENT, vendor_id INTEGER NOT NULL, inventory_item_id INTEGER, name TEXT NOT NULL, category TEXT NOT NULL, price REAL NOT NULL CHECK(price >= 0), currency TEXT NOT NULL DEFAULT 'SAR', image_url TEXT, available INTEGER NOT NULL DEFAULT 1, FOREIGN KEY(vendor_id) REFERENCES marketplace_vendors(id), FOREIGN KEY(inventory_item_id) REFERENCES inventory_items(id))''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS purchase_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, vendor_id INTEGER, vendor_name TEXT NOT NULL, wallet_name TEXT NOT NULL, total REAL NOT NULL CHECK(total > 0), currency TEXT NOT NULL, base_total REAL, base_currency TEXT, exchange_rate REAL, status TEXT NOT NULL, created_at TEXT NOT NULL, journal_entry_id INTEGER, FOREIGN KEY(vendor_id) REFERENCES marketplace_vendors(id), FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id))''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS purchase_order_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, order_number TEXT NOT NULL, product_id INTEGER, product_name TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity > 0), unit_price REAL NOT NULL CHECK(unit_price >= 0), line_total REAL NOT NULL CHECK(line_total >= 0), FOREIGN KEY(order_number) REFERENCES purchase_orders(number), FOREIGN KEY(product_id) REFERENCES marketplace_products(id))''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS inventory_items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sku TEXT NOT NULL DEFAULT '', image_path TEXT, cost_price REAL NOT NULL CHECK(cost_price >= 0), sale_price REAL NOT NULL CHECK(sale_price >= 0), quantity REAL NOT NULL CHECK(quantity >= 0), low_stock_threshold REAL NOT NULL DEFAULT 5 CHECK(low_stock_threshold >= 0), currency TEXT NOT NULL DEFAULT 'SAR', active INTEGER NOT NULL DEFAULT 1)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS sales_invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, customer_name TEXT NOT NULL, payment_account TEXT NOT NULL, currency TEXT NOT NULL, base_total REAL, base_currency TEXT, exchange_rate REAL, total REAL NOT NULL CHECK(total > 0), cost_of_goods_sold REAL NOT NULL CHECK(cost_of_goods_sold >= 0), profit REAL NOT NULL, issued_at TEXT NOT NULL, journal_entry_id INTEGER, status TEXT NOT NULL, FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id))''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS sales_invoice_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_number TEXT NOT NULL, item_id INTEGER NOT NULL, item_name TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity > 0), unit_price REAL NOT NULL CHECK(unit_price >= 0), unit_cost REAL NOT NULL CHECK(unit_cost >= 0), line_total REAL NOT NULL CHECK(line_total >= 0), FOREIGN KEY(invoice_number) REFERENCES sales_invoices(number), FOREIGN KEY(item_id) REFERENCES inventory_items(id))''',
  );
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_marketplace_products_vendor ON marketplace_products(vendor_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_orders_created ON purchase_orders(created_at)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_invoices_issued ON sales_invoices(issued_at)');
  await _addColumnIfMissing(
      db, 'sales_invoices', 'reversal_journal_entry_id', 'INTEGER');
  await _addColumnIfMissing(db, 'sales_invoices', 'reversed_at', 'TEXT');
  await _createInventoryMovementTable(db);
  await _createSalesReturnTables(db);
}

Future<void> _createSalesReturnTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_return_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL,
        invoice_line_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK(quantity > 0),
        amount REAL NOT NULL CHECK(amount > 0),
        journal_entry_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(invoice_number) REFERENCES sales_invoices(number),
        FOREIGN KEY(invoice_line_id) REFERENCES sales_invoice_lines(id),
        FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id)
      )
    ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_return_lines_invoice ON sales_return_lines(invoice_number)');
}

Future<void> _createInventoryMovementTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK(quantity != 0),
        movement_type TEXT NOT NULL,
        reference_type TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        unit_cost REAL NOT NULL CHECK(unit_cost >= 0),
        unit_price REAL NOT NULL CHECK(unit_price >= 0),
        balance_after REAL NOT NULL CHECK(balance_after >= 0),
        created_at TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(item_id) REFERENCES inventory_items(id)
      )
    ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_movements_item_date ON inventory_movements(item_id, created_at)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_movements_reference ON inventory_movements(reference_type, reference_id)');
}
