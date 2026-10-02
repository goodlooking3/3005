import 'package:sqflite/sqflite.dart';

part 'local_database_schema_tables.dart';
part 'local_database_schema_migrations.dart';

class LocalDatabaseSchema {
  static Future<void> createInitialSchema(Database db) async {
    await _createCoreTables(db);
    await _createEnterpriseTables(db);
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
    if (oldVersion < 21)
      await _addColumnIfMissing(db, 'wallet_transactions', 'status',
          "TEXT NOT NULL DEFAULT 'posted'");
    if (oldVersion < 22) await _addWalletAccountMetadata(db);
    if (oldVersion < 23) await _addWalletOperationMetadata(db);
  }
}
