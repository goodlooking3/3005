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
    '''CREATE TABLE IF NOT EXISTS journal_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, voucher_id INTEGER NOT NULL UNIQUE, entry_date TEXT NOT NULL, due_date TEXT, number TEXT NOT NULL, description TEXT NOT NULL, debit_total REAL NOT NULL, credit_total REAL NOT NULL, base_debit_total REAL, base_credit_total REAL, base_currency TEXT, exchange_rate REAL, source TEXT NOT NULL DEFAULT 'voucher', FOREIGN KEY(voucher_id) REFERENCES vouchers(id))''',
  );
  await _createJournalLinesTable(db);
  await _createJournalLineIntegrityGuards(db);
}

Future<void> _createJournalLinesTable(Database db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS journal_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, journal_entry_id INTEGER NOT NULL, account_id INTEGER, party_id INTEGER, account_name TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0 CHECK(debit >= 0), credit REAL NOT NULL DEFAULT 0 CHECK(credit >= 0), currency TEXT NOT NULL DEFAULT 'SAR', base_debit REAL, base_credit REAL, party_name TEXT, FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id))''',
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

Future<void> _ensureAuditTrail(Database db) async {
  for (final column in [
    ('actor_id', "TEXT NOT NULL DEFAULT 'legacy/unknown'"),
    ('session_id', 'TEXT'),
    ('entity_type', "TEXT NOT NULL DEFAULT 'legacy/unknown'"),
    ('entity_id', 'TEXT'),
    ('result', "TEXT NOT NULL DEFAULT 'legacy/unknown'"),
  ]) {
    await _addColumnIfMissing(db, 'audit_log', column.$1, column.$2);
  }

  await db.execute('''
    CREATE TABLE IF NOT EXISTS audit_context (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      actor_id TEXT NOT NULL,
      session_id TEXT
    )
  ''');
  await db.insert(
    'audit_context',
    {'id': 1, 'actor_id': 'local-owner'},
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_actor_created ON audit_log(actor_id, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log(entity_type, entity_id, created_at DESC)',
  );
  await _createAuditLogGuards(db);
  await _createSensitiveChangeAuditTriggers(db);
}

Future<void> _createAuditLogGuards(Database db) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS audit_log_no_update
    BEFORE UPDATE ON audit_log
    BEGIN
      SELECT RAISE(ABORT, 'audit_log is append-only');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS audit_log_no_delete
    BEFORE DELETE ON audit_log
    BEGIN
      SELECT RAISE(ABORT, 'audit_log is append-only');
    END
  ''');
}

Future<void> _createSensitiveChangeAuditTriggers(Database db) async {
  const entityKeys = <String, String>{
    'accounts': 'id',
    'account_currencies': 'account_id',
    'currencies': 'code',
    'exchange_rates': 'id',
    'parties': 'id',
    'company_profile': 'id',
    'user_profile': 'id',
    'vouchers': 'id',
    'voucher_lines': 'id',
    'journal_entries': 'id',
    'journal_lines': 'id',
    'connector_configs': 'id',
    'incoming_messages': 'id',
    'bank_transactions': 'id',
    'wallets': 'id',
    'wallet_accounts': 'id',
    'wallet_transactions': 'id',
    'marketplace_vendors': 'id',
    'marketplace_products': 'id',
    'purchase_orders': 'id',
    'purchase_order_lines': 'id',
    'inventory_items': 'id',
    'inventory_movements': 'id',
    'sales_invoices': 'id',
    'sales_invoice_lines': 'id',
    'sales_return_lines': 'id',
    'remittances': 'id',
    'sync_queue': 'id',
    'accounting_periods': 'id',
    'accounting_policy_settings': 'policy_key',
  };
  final existingRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final existingTables =
      existingRows.map((row) => row['name'] as String).toSet();

  for (final entry in entityKeys.entries) {
    final table = entry.key;
    if (!existingTables.contains(table)) continue;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == entry.value)) continue;
    final newKey = table == 'account_currencies'
        ? "CAST(NEW.account_id AS TEXT) || ':' || NEW.currency"
        : 'CAST(NEW.${entry.value} AS TEXT)';
    final oldKey = table == 'account_currencies'
        ? "CAST(OLD.account_id AS TEXT) || ':' || OLD.currency"
        : 'CAST(OLD.${entry.value} AS TEXT)';

    for (final operation in ['insert', 'update', 'delete']) {
      final isDelete = operation == 'delete';
      final key = isDelete ? oldKey : newKey;
      final triggerName = 'audit_${table}_$operation';
      final trigger = '''
        CREATE TRIGGER IF NOT EXISTS $triggerName
        AFTER ${operation.toUpperCase()} ON $table
        BEGIN
          INSERT INTO audit_log
            (created_at, actor_id, session_id, entity_type, entity_id, action, result, details)
          VALUES (
            strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
            COALESCE((SELECT actor_id FROM audit_context WHERE id = 1), 'local-owner'),
            (SELECT session_id FROM audit_context WHERE id = 1),
            '$table', $key, 'db.$operation', 'success',
            'database-trigger'
          );
        END
      ''';
      await db.execute(trigger);
    }
  }
}

Future<void> _ensurePhase2AccountingControls(Database db) async {
  await _addColumnIfMissing(
    db,
    'journal_entries',
    'reversal_of_id',
    'INTEGER REFERENCES journal_entries(id)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS accounting_periods (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'closed')),
      created_at TEXT NOT NULL,
      closed_at TEXT,
      closed_by TEXT,
      CHECK(start_date <= end_date)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS document_sequences (
      prefix TEXT NOT NULL,
      period_key TEXT NOT NULL,
      current_value INTEGER NOT NULL DEFAULT 0 CHECK(current_value >= 0),
      PRIMARY KEY(prefix, period_key)
    )
  ''');

  final duplicateVouchers = await db.rawQuery('''
    SELECT number, COUNT(*) AS row_count FROM vouchers
    GROUP BY number COLLATE NOCASE HAVING COUNT(*) > 1 LIMIT 1
  ''');
  if (duplicateVouchers.isNotEmpty) {
    throw StateError(
      'PHASE2 migration stopped: duplicate voucher numbers require review',
    );
  }
  final duplicateEntries = await db.rawQuery('''
    SELECT number, COUNT(*) AS row_count FROM journal_entries
    GROUP BY number COLLATE NOCASE HAVING COUNT(*) > 1 LIMIT 1
  ''');
  if (duplicateEntries.isNotEmpty) {
    throw StateError(
      'PHASE2 migration stopped: duplicate journal numbers require review',
    );
  }
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_vouchers_number_unique ON vouchers(number COLLATE NOCASE)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_number_unique ON journal_entries(number COLLATE NOCASE)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_reversal_unique ON journal_entries(reversal_of_id) WHERE reversal_of_id IS NOT NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_accounting_periods_dates ON accounting_periods(start_date, end_date, status)',
  );
  await _createAccountingPeriodGuards(db);
  await _createJournalAppendOnlyGuards(db);
  await _createJournalPeriodGuard(db);
  await _createAccountingRoleGuards(db);
  await _createSensitiveChangeAuditTriggers(db);
  await db.insert(
    'user_profile',
    {'id': 1, 'display_name': 'المستخدم', 'role': 'admin'},
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<void> _createAccountingPeriodGuards(Database db) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS accounting_periods_no_overlap_insert
    BEFORE INSERT ON accounting_periods
    WHEN EXISTS (
      SELECT 1 FROM accounting_periods p
      WHERE NEW.start_date <= p.end_date AND NEW.end_date >= p.start_date
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting periods cannot overlap');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS accounting_periods_no_overlap_update
    BEFORE UPDATE OF start_date, end_date ON accounting_periods
    WHEN EXISTS (
      SELECT 1 FROM accounting_periods p
      WHERE p.id != OLD.id
        AND NEW.start_date <= p.end_date AND NEW.end_date >= p.start_date
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting periods cannot overlap');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS accounting_periods_closed_no_update
    BEFORE UPDATE ON accounting_periods WHEN OLD.status = 'closed'
    BEGIN
      SELECT RAISE(ABORT, 'closed accounting period is immutable');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS accounting_periods_closed_no_delete
    BEFORE DELETE ON accounting_periods WHEN OLD.status = 'closed'
    BEGIN
      SELECT RAISE(ABORT, 'closed accounting period is immutable');
    END
  ''');
}

Future<void> _createJournalAppendOnlyGuards(Database db) async {
  for (final table in ['journal_entries', 'journal_lines']) {
    for (final operation in ['UPDATE', 'DELETE']) {
      final name = 'phase2_${table}_${operation.toLowerCase()}_blocked';
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS $name
        BEFORE $operation ON $table
        BEGIN
          SELECT RAISE(ABORT, 'posted journal is append-only; create a reversal');
        END
      ''');
    }
  }
}

Future<void> _createJournalPeriodGuard(Database db) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS journal_entry_open_period_required
    BEFORE INSERT ON journal_entries
    WHEN EXISTS (SELECT 1 FROM accounting_periods)
      AND NOT EXISTS (
        SELECT 1 FROM accounting_periods p
        WHERE substr(NEW.entry_date, 1, 10) BETWEEN p.start_date AND p.end_date
          AND p.status = 'open'
      )
    BEGIN
      SELECT RAISE(ABORT, 'journal entry date is outside an open accounting period');
    END
  ''');
}
