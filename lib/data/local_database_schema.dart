import 'package:sqflite/sqflite.dart';

part 'local_database_schema_tables.dart';
part 'local_database_schema_migrations.dart';
part 'local_database_schema_accounting_guards.dart';
part 'local_database_schema_business_links.dart';
part 'local_database_schema_policies.dart';

class LocalDatabaseSchema {
  static Future<void> createInitialSchema(Database db) async {
    await _createCoreTables(db);
    await _createEnterpriseTables(db);
    await _ensureAccountingPolicySettings(db);
    await _ensureBusinessPartyLinks(db);
    await _ensureAuditTrail(db);
    await _ensurePhase2AccountingControls(db);
  }

  static Future<void> upgrade(Database db, int oldVersion) async {
    if (oldVersion < 2) await _createAccountingTables(db);
    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        'sync_queue',
        'idempotency_key',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        'sync_queue',
        'remote_version',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 4) await _createEnterpriseTables(db);
    if (oldVersion < 5) await _createJournalTable(db);
    if (oldVersion < 6) await _createWalletTables(db);
    if (oldVersion < 7) await _addWalletTransactionReferences(db);
    if (oldVersion < 8) await _createJournalLinesTable(db);
    if (oldVersion < 9) {
      await _backfillJournalLines(db);
      await _assertJournalLinesComplete(db);
      await _createJournalLineIntegrityGuards(db);
    }
    if (oldVersion < 10) await _createCommerceTables(db);
    if (oldVersion < 11) {
      await _addColumnIfMissing(
          db, 'sales_invoices', 'reversal_journal_entry_id', 'INTEGER');
      await _addColumnIfMissing(db, 'sales_invoices', 'reversed_at', 'TEXT');
      await _createInventoryMovementTable(db);
    }
    if (oldVersion < 12) await _createSalesReturnTables(db);
    if (oldVersion < 13) {
      await _addColumnIfMissing(
        db,
        'marketplace_products',
        'inventory_item_id',
        'INTEGER',
      );
    }
    if (oldVersion < 14) await _createCurrencyTables(db);
    if (oldVersion < 15) await _addCurrencyValuationColumns(db);
    if (oldVersion < 16) {
      await _addColumnIfMissing(db, 'wallet_accounts', 'account_id', 'INTEGER');
    }
    if (oldVersion < 17) await _addMultiCurrencyAccounting(db);
    if (oldVersion < 18) {
      await _addColumnIfMissing(
          db, 'connector_configs', 'linked_account_id', 'INTEGER');
      await _createBankSandboxTable(db);
    }
    if (oldVersion < 19) await _createWalletIntegrityIndexes(db);
    if (oldVersion < 20) await _addWalletAccountReferenceColumns(db);
    if (oldVersion < 21) {
      await _addColumnIfMissing(db, 'wallet_transactions', 'status',
          "TEXT NOT NULL DEFAULT 'posted'");
    }
    if (oldVersion < 22) await _addWalletAccountMetadata(db);
    if (oldVersion < 23) await _addWalletOperationMetadata(db);
    if (oldVersion < 24) {
      await _addColumnIfMissing(
        db,
        'sales_invoices',
        'cost_journal_entry_id',
        'INTEGER REFERENCES journal_entries(id)',
      );
      await _addColumnIfMissing(
        db,
        'sales_return_lines',
        'cost_journal_entry_id',
        'INTEGER REFERENCES journal_entries(id)',
      );
    }
    if (oldVersion < 25) {
      await _addColumnIfMissing(
          db, 'purchase_orders', 'shipping', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'purchase_orders', 'discount', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'purchase_orders', 'recoverable_tax', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'purchase_orders', 'nonrecoverable_tax',
          'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'purchase_order_lines', 'unit_cost', 'REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 26) {
      await _addColumnIfMissing(db, 'parties', 'account_id', 'INTEGER');
      await _addColumnIfMissing(db, 'voucher_lines', 'party_id', 'INTEGER');
      await _addColumnIfMissing(db, 'journal_lines', 'party_id', 'INTEGER');
    }
    if (oldVersion < 27) {
      await _addColumnIfMissing(db, 'accounts', 'name_ar', 'TEXT');
      await _addColumnIfMissing(db, 'accounts', 'name_en', 'TEXT');
      await _addColumnIfMissing(db, 'parties', 'name_ar', 'TEXT');
      await _addColumnIfMissing(db, 'parties', 'name_en', 'TEXT');
      await _addColumnIfMissing(db, 'parties', 'address', 'TEXT');
      await _addColumnIfMissing(
          db, 'parties', 'credit_limit', 'REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 28) await _ensureAuditTrail(db);
    if (oldVersion < 29) await _ensurePhase2AccountingControls(db);
    if (oldVersion < 30) await _ensureBusinessPartyLinks(db);
    if (oldVersion < 31) {
      await _addColumnIfMissing(db, 'journal_entries', 'due_date', 'TEXT');
    }
    if (oldVersion < 32) {
      await _ensureAccountingPolicySettings(db);
      await _ensureAuditTrail(db);
    }
  }
}
