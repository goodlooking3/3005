part of 'local_database_schema.dart';

Future<void> _addWalletTransactionReferences(Database db) async {
  for (final column in [
    ('related_module', 'TEXT'),
    ('related_entity_id', 'TEXT'),
    ('journal_entry_id', 'INTEGER'),
  ]) await _addColumnIfMissing(db, 'wallet_transactions', column.$1, column.$2);
}

Future<void> _addWalletOperationMetadata(Database db) async {
  for (final column in [
    ('wallet_transactions', 'fee_amount', 'REAL'),
    ('wallet_transactions', 'fee_currency', 'TEXT'),
    ('wallet_transactions', 'source_reference', 'TEXT'),
    ('wallet_transactions', 'raw_payload', 'TEXT'),
  ]) await _addColumnIfMissing(db, column.$1, column.$2, column.$3);
  await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_transactions_source_reference ON wallet_transactions(source_reference) WHERE source_reference IS NOT NULL AND source_reference <> \'\'');
}

Future<void> _createJournalTable(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS journal_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, voucher_id INTEGER NOT NULL UNIQUE, entry_date TEXT NOT NULL, number TEXT NOT NULL, description TEXT NOT NULL, debit_total REAL NOT NULL, credit_total REAL NOT NULL, base_debit_total REAL, base_credit_total REAL, base_currency TEXT, exchange_rate REAL, source TEXT NOT NULL DEFAULT 'voucher', FOREIGN KEY(voucher_id) REFERENCES vouchers(id))''',
  );
  await _createJournalLinesTable(db);
  await _createJournalLineIntegrityGuards(db);
}

Future<void> _createJournalLinesTable(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS journal_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, journal_entry_id INTEGER NOT NULL, account_id INTEGER, account_name TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0 CHECK(debit >= 0), credit REAL NOT NULL DEFAULT 0 CHECK(credit >= 0), currency TEXT NOT NULL DEFAULT 'SAR', base_debit REAL, base_credit REAL, party_name TEXT, FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id))''',
  );
}

Future<void> _createAccountCurrenciesTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS account_currencies (
        account_id INTEGER NOT NULL,
        currency TEXT NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(account_id, currency),
        FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_account_currencies_currency ON account_currencies(currency)',
  );
}

Future<void> _addMultiCurrencyAccounting(Database db) async {
  await _createAccountCurrenciesTable(db);
  await _addColumnIfMissing(
      db, 'voucher_lines', 'currency', "TEXT NOT NULL DEFAULT 'SAR'");
  await _addColumnIfMissing(db, 'voucher_lines', 'base_debit', 'REAL');
  await _addColumnIfMissing(db, 'voucher_lines', 'base_credit', 'REAL');
  await _addColumnIfMissing(
      db, 'journal_lines', 'currency', "TEXT NOT NULL DEFAULT 'SAR'");
  await _addColumnIfMissing(db, 'journal_lines', 'base_debit', 'REAL');
  await _addColumnIfMissing(db, 'journal_lines', 'base_credit', 'REAL');
  await db.execute('''
      INSERT OR IGNORE INTO account_currencies(account_id, currency, is_primary)
      SELECT id, currency, 1 FROM accounts
    ''');
  await db.execute('''
      UPDATE voucher_lines SET currency = COALESCE(
        (SELECT currency FROM vouchers WHERE vouchers.id = voucher_lines.voucher_id), 'SAR')
    ''');
  await db.execute('''
      UPDATE journal_lines SET currency = COALESCE(
        (SELECT v.currency FROM journal_entries je JOIN vouchers v ON v.id = je.voucher_id
         WHERE je.id = journal_lines.journal_entry_id), 'SAR')
    ''');
  await db.execute('''
      UPDATE voucher_lines SET
        base_debit = debit * COALESCE((SELECT exchange_rate FROM vouchers v WHERE v.id = voucher_lines.voucher_id), 1),
        base_credit = credit * COALESCE((SELECT exchange_rate FROM vouchers v WHERE v.id = voucher_lines.voucher_id), 1)
      WHERE base_debit IS NULL OR base_credit IS NULL
    ''');
  await db.execute('''
      UPDATE journal_lines SET
        base_debit = debit * COALESCE((SELECT exchange_rate FROM journal_entries je WHERE je.id = journal_lines.journal_entry_id), 1),
        base_credit = credit * COALESCE((SELECT exchange_rate FROM journal_entries je WHERE je.id = journal_lines.journal_entry_id), 1)
      WHERE base_debit IS NULL OR base_credit IS NULL
    ''');
}

Future<void> _backfillJournalLines(Database db) async {
  await db.execute('''
      INSERT INTO journal_lines
        (journal_entry_id, account_id, account_name, debit, credit, party_name)
      SELECT je.id, vl.account_id, vl.account_name, vl.debit, vl.credit, vl.party_name
      FROM journal_entries je
      INNER JOIN voucher_lines vl ON vl.voucher_id = je.voucher_id
      WHERE NOT EXISTS (
        SELECT 1 FROM journal_lines existing
        WHERE existing.journal_entry_id = je.id
      )
    ''');
}

Future<void> _assertJournalLinesComplete(Database db) async {
  final incomplete = await db.rawQuery('''
      SELECT je.id
      FROM journal_entries je
      WHERE (
        SELECT COUNT(*) FROM voucher_lines vl WHERE vl.voucher_id = je.voucher_id
      ) != (
        SELECT COUNT(*) FROM journal_lines jl WHERE jl.journal_entry_id = je.id
      )
      OR (SELECT COUNT(*) FROM journal_lines jl WHERE jl.journal_entry_id = je.id) = 0
      OR ABS(
        (SELECT COALESCE(SUM(jl.debit), 0) FROM journal_lines jl WHERE jl.journal_entry_id = je.id)
        - je.debit_total
      ) > 0.000001
      OR ABS(
        (SELECT COALESCE(SUM(jl.credit), 0) FROM journal_lines jl WHERE jl.journal_entry_id = je.id)
        - je.credit_total
      ) > 0.000001
      OR EXISTS (
        SELECT 1 FROM journal_lines jl
        WHERE jl.journal_entry_id = je.id
          AND ((jl.debit = 0 AND jl.credit = 0) OR (jl.debit > 0 AND jl.credit > 0))
      )
      LIMIT 1
    ''');
  if (incomplete.isNotEmpty) {
    throw StateError(
      'Migration stopped: journal entry has incomplete journal lines',
    );
  }
}

Future<void> _createJournalLineIntegrityGuards(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines(journal_entry_id)',
  );
  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS journal_lines_validate_insert
      BEFORE INSERT ON journal_lines
      WHEN NEW.debit = 0 AND NEW.credit = 0 OR NEW.debit > 0 AND NEW.credit > 0
      BEGIN
        SELECT RAISE(ABORT, 'Journal line must have exactly one side');
      END
    ''');
  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS journal_lines_validate_update
      BEFORE UPDATE OF debit, credit ON journal_lines
      WHEN NEW.debit = 0 AND NEW.credit = 0 OR NEW.debit > 0 AND NEW.credit > 0
      BEGIN
        SELECT RAISE(ABORT, 'Journal line must have exactly one side');
      END
    ''');
}

Future<void> _addColumnIfMissing(
  Database db,
  String table,
  String column,
  String definition,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (!columns.any((row) => row['name'] == column)) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}

Future<void> _addCurrencyValuationColumns(Database db) async {
  for (final column in [
    ('vouchers', 'base_amount', 'REAL'),
    ('vouchers', 'base_currency', 'TEXT'),
    ('vouchers', 'exchange_rate', 'REAL'),
    ('wallet_transactions', 'base_amount', 'REAL'),
    ('wallet_transactions', 'base_currency', 'TEXT'),
    ('wallet_transactions', 'exchange_rate', 'REAL'),
    ('purchase_orders', 'base_total', 'REAL'),
    ('purchase_orders', 'base_currency', 'TEXT'),
    ('purchase_orders', 'exchange_rate', 'REAL'),
    ('sales_invoices', 'base_total', 'REAL'),
    ('sales_invoices', 'base_currency', 'TEXT'),
    ('sales_invoices', 'exchange_rate', 'REAL'),
    ('journal_entries', 'base_debit_total', 'REAL'),
    ('journal_entries', 'base_credit_total', 'REAL'),
    ('journal_entries', 'base_currency', 'TEXT'),
    ('journal_entries', 'exchange_rate', 'REAL'),
  ]) {
    await _addColumnIfMissing(db, column.$1, column.$2, column.$3);
  }
}
