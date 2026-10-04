import 'package:sqflite/sqflite.dart';

import '../../../../data/local_database.dart';
import '../../../../data/accounting_repository.dart';
import '../../domain/models/wallet_model.dart';
import '../../domain/models/wallet_transaction.dart';
import '../../domain/repositories/i_wallet_repository.dart';
import '../../application/accounting_ledger_bridge.dart';

class WalletRepositoryImpl implements IWalletRepository {
  final AccountingLedgerBridge ledgerBridge;
  WalletRepositoryImpl({AccountingLedgerBridge? ledgerBridge})
      : ledgerBridge =
            ledgerBridge ?? AccountingLedgerBridge(AccountingRepository());

  Future<Database> get _db => LocalDatabase.instance.database;

  @override
  Future<List<Wallet>> wallets() async {
    final db = await _db;
    final walletRows = await db.query(
      'wallets',
      orderBy: 'name COLLATE NOCASE',
    );
    final result = <Wallet>[];
    for (final row in walletRows) {
      final accounts = await db.rawQuery('''
        SELECT wa.*, a.code AS accounting_code, a.name AS accounting_name
        FROM wallet_accounts wa
        LEFT JOIN accounts a ON a.id = wa.account_id
        WHERE wa.wallet_id = ? AND wa.active = 1
        ORDER BY wa.id ASC
      ''', [row['id']]);
      result.add(
        Wallet(
          id: row['id']! as String,
          name: row['name']! as String,
          provider: WalletProviderConfig(
            id: row['provider_id']! as String,
            name: row['provider_name']! as String,
            deepLink: row['deep_link'] as String?,
          ),
          accounts: accounts.map(WalletAccount.fromMap).toList(growable: false),
        ),
      );
    }
    return result;
  }

  @override
  Future<List<WalletTransaction>> transactions({
    WalletTransactionFilter filter = const WalletTransactionFilter(),
  }) async {
    final db = await _db;
    final clauses = <String>[];
    final args = <Object?>[];
    if (filter.type != null) {
      clauses.add('type = ?');
      args.add(filter.type!.name);
    }
    if (filter.currency != null) {
      clauses.add('currency = ?');
      args.add(filter.currency);
    }
    if (filter.status != null) {
      clauses.add('status = ?');
      args.add(filter.status);
    }
    if (filter.from != null) {
      clauses.add('date >= ?');
      args.add(filter.from!.toIso8601String());
    }
    if (filter.to != null) {
      clauses.add('date <= ?');
      args.add(filter.to!.toIso8601String());
    }
    if (filter.query.trim().isNotEmpty) {
      clauses.add('(note LIKE ? OR from_account LIKE ? OR to_account LIKE ?)');
      final term = '%${filter.query.trim()}%';
      args.addAll([term, term, term]);
    }
    if (filter.walletId != null) {
      final linked = await db.query(
        'wallet_accounts',
        columns: ['id'],
        where: 'wallet_id = ?',
        whereArgs: [filter.walletId],
      );
      if (linked.isEmpty) return const [];
      final ids = linked.map((row) => row['id']).toList();
      clauses.add(
        '(from_wallet_account_id IN (${List.filled(ids.length, '?').join(',')}) '
        'OR to_wallet_account_id IN (${List.filled(ids.length, '?').join(',')}))',
      );
      args.addAll(ids);
      args.addAll(ids);
    }
    final rows = await db.query(
      'wallet_transactions',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC',
    );
    return rows.map(WalletTransaction.fromMap).toList(growable: false);
  }

  @override
  Future<int> saveWallet(Wallet wallet) => LocalDatabase.instance.write(
        (db) => db.insert(
            'wallets',
            {
              'id': wallet.id,
              'name': wallet.name,
              'provider_id': wallet.provider.id,
              'provider_name': wallet.provider.name,
              'deep_link': wallet.provider.deepLink,
            },
            conflictAlgorithm: ConflictAlgorithm.replace),
      );

  @override
  Future<void> saveWalletWithAccount(Wallet wallet, WalletAccount account) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          await txn.insert(
            'wallets',
            {
              'id': wallet.id,
              'name': wallet.name.trim(),
              'provider_id': wallet.provider.id,
              'provider_name': wallet.provider.name.trim(),
              'deep_link': wallet.provider.deepLink,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _validateWalletAccountLink(txn, account);
          await txn.insert(
            'wallet_accounts',
            _walletAccountValues(account),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
      });

  @override
  Future<int> saveAccount(WalletAccount account) =>
      LocalDatabase.instance.write((db) async {
        if (account.name.trim().isEmpty || account.currency.trim().isEmpty) {
          throw ArgumentError('بيانات حساب المحفظة غير مكتملة');
        }
        await _validateWalletAccountLink(db, account);
        final values = _walletAccountValues(account);
        if (account.id == null) {
          return db.insert('wallet_accounts', values);
        }
        final updated = await db.update(
          'wallet_accounts',
          values,
          where: 'id = ? AND wallet_id = ?',
          whereArgs: [account.id, account.walletId],
        );
        if (updated == 0) throw StateError('حساب المحفظة غير موجود');
        return account.id!;
      });

  @override
  Future<void> saveAccounts(List<WalletAccount> accounts) async {
    if (accounts.isEmpty) throw ArgumentError('اختر عملة واحدة على الأقل');
    await LocalDatabase.instance.write((db) async {
      await db.transaction((txn) async {
        final identities = <String>{};
        for (final account in accounts) {
          if (account.id != null ||
              account.name.trim().isEmpty ||
              account.currency.trim().isEmpty) {
            throw ArgumentError('بيانات حساب المحفظة غير صالحة');
          }
          final identity =
              '${account.walletId}|${account.name.trim().toLowerCase()}|${account.currency.trim().toUpperCase()}';
          if (!identities.add(identity)) {
            throw StateError('تكررت عملة الحساب في طلب الحفظ');
          }
          await _validateWalletAccountLink(txn, account);
        }
        for (final account in accounts) {
          await txn.insert(
            'wallet_accounts',
            _walletAccountValues(account),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      });
    });
  }

  Future<void> _validateWalletAccountLink(
    DatabaseExecutor db,
    WalletAccount account,
  ) async {
    final accountId = account.accountId;
    final currency = account.currency.trim().toUpperCase();
    if (accountId == null || accountId <= 0 || currency.isEmpty) {
      throw StateError('يجب ربط حساب المحفظة بحساب نقدي أو بنكي وعملة صالحة');
    }
    final rows = await db.query(
      'accounts',
      columns: ['id', 'currency', 'is_group'],
      where: "id = ? AND active = 1 AND kind IN ('cash', 'bank')",
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty || (rows.single['is_group'] as int? ?? 0) == 1) {
      throw StateError('اختر حسابًا نقديًا أو بنكيًا تفصيليًا ونشطًا');
    }
    final permitted = await db.query(
      'account_currencies',
      columns: ['currency'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final allowed = permitted.isEmpty
        ? <String>{(rows.single['currency']! as String).toUpperCase()}
        : permitted.map((row) => (row['currency']! as String).toUpperCase()).toSet();
    if (!allowed.contains(currency)) {
      throw StateError('العملة المحددة غير مسموحة لهذا الحساب المحاسبي');
    }
  }

  Map<String, Object?> _walletAccountValues(WalletAccount account) => {
        'wallet_id': account.walletId,
        'name': account.name.trim(),
        'currency': account.currency.trim().toUpperCase(),
        'balance': account.balance,
        'active': account.active ? 1 : 0,
        'account_id': account.accountId,
        'external_type': account.externalType,
        'external_id': account.externalId,
        'connection_status': account.connectionStatus,
        'balance_source': account.balanceSource,
        'last_synced_at': account.lastSyncedAt?.toIso8601String(),
        'last_error': account.lastError,
      };

  @override
  Future<int> saveTransaction(WalletTransaction transaction) async {
    return LocalDatabase.instance.write((db) async {
      return db.transaction((txn) async {
        final reference = (transaction.sourceReference ?? transaction.reference)?.trim();
        if (reference != null && reference.isNotEmpty) {
          final existing = await txn.query(
            'wallet_transactions',
            columns: ['id'],
            where: transaction.sourceReference == null
                ? 'reference = ?'
                : 'source_reference = ?',
            whereArgs: [reference],
            limit: 1,
          );
          if (existing.isNotEmpty) return existing.single['id']! as int;
        }
        final posted = await ledgerBridge.postInTransaction(txn, transaction);
        final sourceId = await _walletAccountId(
          txn, transaction.fromAccount, transaction.currency,
        );
        final destinationId = await _walletAccountId(
          txn, transaction.toAccount, transaction.currency,
        );
        return txn.insert('wallet_transactions', _transactionMap(
          posted.copyWith(
            fromWalletAccountId: sourceId,
            toWalletAccountId: destinationId,
          ),
        ));
      });
    });
  }

  Future<int?> _walletAccountId(
    DatabaseExecutor db,
    String name,
    String currency,
  ) async {
    final rows = await db.query(
      'wallet_accounts',
      columns: ['id'],
      where: 'name = ? AND currency = ? AND active = 1',
      whereArgs: [name.trim(), currency.trim().toUpperCase()],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id']! as int;
  }

  @override
  Future<void> importTransactions(List<WalletTransaction> transactions) async {
    for (final item in transactions) {
      await saveTransaction(item);
    }
  }

  Map<String, Object?> _transactionMap(WalletTransaction transaction) => {
        'from_wallet_account_id': transaction.fromWalletAccountId,
        'to_wallet_account_id': transaction.toWalletAccountId,
        'from_account': transaction.fromAccount,
        'to_account': transaction.toAccount,
        'type': transaction.type.name,
        'amount': transaction.amount,
        'currency': transaction.currency,
        'base_amount': transaction.baseAmount,
        'base_currency': transaction.baseCurrency,
        'exchange_rate': transaction.exchangeRate,
        'fee_amount': transaction.feeAmount,
        'fee_currency': transaction.feeCurrency,
        'note': transaction.note,
        'date': transaction.date.toIso8601String(),
        'reference': transaction.reference,
        'source_reference': transaction.sourceReference,
        'raw_payload': transaction.rawPayload,
        'related_module': transaction.relatedModule,
        'related_entity_id': transaction.relatedEntityId,
        'journal_entry_id': transaction.journalEntryId,
        'status': transaction.status,
      };
}
