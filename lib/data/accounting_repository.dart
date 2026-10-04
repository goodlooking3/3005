import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../core/accounting.dart';
import '../core/connector_models.dart';
import '../core/models.dart';
import 'local_database.dart';
import 'currency_policy.dart';
import '../features/accounting/domain/journal_entry.dart';

class AuditRecord {
  final int? id;
  final DateTime createdAt;
  final String action;
  final String details;
  const AuditRecord({
    this.id,
    required this.createdAt,
    required this.action,
    required this.details,
  });
}

class AccountingRepository {
  Future<Database> get _db => LocalDatabase.instance.database;

  Future<int> insertSalesJournal(
    Transaction txn, {
    required String number,
    required String description,
    required double amount,
    required String currency,
    required DateTime date,
    required int cashAccountId,
    required int salesAccountId,
    required String paymentAccount,
    required String customerName,
  }) async {
    if (!amount.isFinite ||
        amount <= 0 ||
        number.trim().isEmpty ||
        currency.trim().isEmpty ||
        paymentAccount.trim().isEmpty) {
      throw ArgumentError('بيانات قيد البيع غير صالحة');
    }
    await _validateAccountIds(txn, [cashAccountId, salesAccountId]);
    await _validateAccountCurrencyIds(txn, [cashAccountId, salesAccountId], currency);
    final valuation = await currencyPolicy.value(
      db: txn,
      amount: amount,
      currency: currency,
      at: date,
    );
    final voucherId = await txn.insert('vouchers', {
      'number': number.trim(),
      'type': VoucherType.receipt.name,
      'description': description.trim(),
      'amount': amount,
      'currency': currency,
      'base_amount': valuation.baseAmount,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'date': date.toIso8601String(),
      'recipient_name': customerName,
      'debit_account_id': cashAccountId,
      'credit_account_id': salesAccountId,
    });
    final journalId = await txn.insert('journal_entries', {
      'voucher_id': voucherId,
      'entry_date': date.toIso8601String(),
      'number': number.trim(),
      'description': description.trim(),
      'debit_total': amount,
      'credit_total': amount,
      'base_debit_total': valuation.baseAmount,
      'base_credit_total': valuation.baseAmount,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'source': 'sales',
    });
    final lines = [
      {
        'account_id': cashAccountId,
        'account_name': paymentAccount.trim(),
        'debit': amount,
        'credit': 0,
        'party_name': customerName
      },
      {
        'account_id': salesAccountId,
        'account_name': 'المبيعات',
        'debit': 0,
        'credit': amount,
        'party_name': null
      },
    ];
    for (final line in lines) {
      await txn.insert('voucher_lines', {
        'voucher_id': voucherId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit': (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit': (line['credit'] as num).toDouble() * valuation.exchangeRate,
      });
      await txn.insert('journal_lines', {
        'journal_entry_id': journalId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit': (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit': (line['credit'] as num).toDouble() * valuation.exchangeRate,
      });
    }
    return journalId;
  }

  Future<int> insertSalesReversalJournal(
    Transaction txn, {
    required String number,
    required String description,
    required double amount,
    required String currency,
    required DateTime date,
    required int cashAccountId,
    required int salesAccountId,
    required String paymentAccount,
    required String customerName,
    required String source,
  }) async {
    if (!amount.isFinite || amount <= 0 || number.trim().isEmpty) {
      throw ArgumentError('بيانات القيد العكسي غير صالحة');
    }
    await _validateAccountIds(txn, [salesAccountId, cashAccountId]);
    await _validateAccountCurrencyIds(txn, [salesAccountId, cashAccountId], currency);
    final valuation = await currencyPolicy.value(
      db: txn,
      amount: amount,
      currency: currency,
      at: date,
    );
    final voucherId = await txn.insert('vouchers', {
      'number': number.trim(),
      'type': VoucherType.journal.name,
      'description': description.trim(),
      'amount': amount,
      'currency': currency,
      'base_amount': valuation.baseAmount,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'date': date.toIso8601String(),
      'payer_name': customerName,
      'debit_account_id': salesAccountId,
      'credit_account_id': cashAccountId,
    });
    final journalId = await txn.insert('journal_entries', {
      'voucher_id': voucherId,
      'entry_date': date.toIso8601String(),
      'number': number.trim(),
      'description': description.trim(),
      'debit_total': amount,
      'credit_total': amount,
      'base_debit_total': valuation.baseAmount,
      'base_credit_total': valuation.baseAmount,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'source': source,
    });
    final lines = [
      {
        'account_id': salesAccountId,
        'account_name': 'المبيعات',
        'debit': amount,
        'credit': 0,
        'party_name': null
      },
      {
        'account_id': cashAccountId,
        'account_name': paymentAccount.trim(),
        'debit': 0,
        'credit': amount,
        'party_name': customerName
      },
    ];
    for (final line in lines) {
      await txn.insert('voucher_lines', {
        'voucher_id': voucherId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit': (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit': (line['credit'] as num).toDouble() * valuation.exchangeRate,
      });
      await txn.insert('journal_lines', {
        'journal_entry_id': journalId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit': (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit': (line['credit'] as num).toDouble() * valuation.exchangeRate,
      });
    }
    return journalId;
  }

  Future<int> insertVoucher(Voucher voucher) => LocalDatabase.instance.write(
        (db) =>
            db.transaction((txn) => insertVoucherInTransaction(txn, voucher)),
      );

  Future<int> insertVoucherInTransaction(
    Transaction txn,
    Voucher voucher,
  ) async {
    if (!voucher.amount.isFinite || voucher.amount <= 0) {
      throw ArgumentError('Voucher amount must be positive');
    }
    if (voucher.lines.isEmpty || !voucher.lines.every((line) => line.isValid)) {
      throw ArgumentError('Voucher lines must be balanced');
    }
    if (voucher.number.trim().isEmpty ||
        voucher.description.trim().isEmpty ||
        voucher.currency.trim().isEmpty) {
      throw ArgumentError(
          'Voucher number, description and currency are required',
      );
    }
    final duplicate = await txn.query(
      'vouchers',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [voucher.number.trim()],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw StateError('رقم السند مستخدم مسبقًا: ${voucher.number.trim()}');
    }
    await _validatePostingAccounts(txn, voucher);
    await _validatePostingCurrencies(txn, voucher);
    await _validatePartyLinks(txn, voucher);
    final valuation = await currencyPolicy.value(
      db: txn,
      amount: voucher.amount,
      currency: voucher.currency,
      at: voucher.date,
    );
    final lineValuations = <CurrencyValuation>[];
    for (final line in voucher.lines) {
      lineValuations.add(await currencyPolicy.value(
        db: txn,
        amount: line.debit > 0 ? line.debit : line.credit,
        currency: _lineCurrency(voucher, line),
        at: voucher.date,
      ));
    }
    final baseDebitTotal = voucher.lines.asMap().entries.fold<double>(
      0,
      (total, entry) => total + entry.value.debit * lineValuations[entry.key].exchangeRate,
    );
    final baseCreditTotal = voucher.lines.asMap().entries.fold<double>(
      0,
      (total, entry) => total + entry.value.credit * lineValuations[entry.key].exchangeRate,
    );
    if ((baseDebitTotal - baseCreditTotal).abs() > 0.000001 ||
        (baseDebitTotal - valuation.baseAmount).abs() > 0.000001) {
      throw ArgumentError('يجب توازن المدين والدائن بعد تحويلهما إلى العملة الأساسية');
    }
    final id = await txn.insert('vouchers', {
      'number': voucher.number.trim(),
      'type': voucher.type.name,
      'description': voucher.description.trim(),
      'amount': voucher.amount,
      'currency': voucher.currency,
      'base_amount': valuation.baseAmount,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'date': voucher.date.toIso8601String(),
      'recipient_name': voucher.recipientName,
      'payer_name': voucher.payerName,
      'debit_account_id': voucher.debitAccountId,
      'credit_account_id': voucher.creditAccountId,
    });
    for (var index = 0; index < voucher.lines.length; index++) {
      final line = voucher.lines[index];
      final lineValuation = lineValuations[index];
      await txn.insert('voucher_lines', {
        'voucher_id': id,
        'account_id': line.accountId,
        'party_id': line.partyId,
        'account_name': line.accountName,
        'debit': line.debit,
        'credit': line.credit,
        'currency': lineValuation.currency,
        'base_debit': line.debit * lineValuation.exchangeRate,
        'base_credit': line.credit * lineValuation.exchangeRate,
        'party_name': line.partyName,
      });
    }
    await txn.insert('journal_entries', {
      'voucher_id': id,
      'entry_date': voucher.date.toIso8601String(),
      'number': voucher.number.trim(),
      'description': voucher.description.trim(),
      'debit_total': baseDebitTotal,
      'credit_total': baseCreditTotal,
      'base_debit_total': baseDebitTotal,
      'base_credit_total': baseCreditTotal,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'source': 'voucher',
    });
    final journalRows = await txn.query(
      'journal_entries',
      columns: ['id'],
      where: 'voucher_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (journalRows.isEmpty) {
      throw StateError('Journal entry was not created for voucher $id');
    }
    final journalId = journalRows.single['id'] as int;
    for (var index = 0; index < voucher.lines.length; index++) {
      final line = voucher.lines[index];
      final lineValuation = lineValuations[index];
      await txn.insert('journal_lines', {
        'journal_entry_id': journalId,
        'account_id': line.accountId,
        'party_id': line.partyId,
        'account_name': line.accountName,
        'debit': line.debit,
        'credit': line.credit,
        'currency': lineValuation.currency,
        'base_debit': line.debit * lineValuation.exchangeRate,
        'base_credit': line.credit * lineValuation.exchangeRate,
        'party_name': line.partyName,
      });
    }
    await txn.insert('audit_log', {
      'created_at': DateTime.now().toIso8601String(),
      'action': 'create_voucher',
      'details':
          '${voucher.type.name}:${voucher.number} amount=${voucher.amount}',
    });
    await txn.insert('audit_log', {
      'created_at': DateTime.now().toIso8601String(),
      'action': 'post_journal_entry',
      'details':
          'journal=$journalId voucher=$id debit=$baseDebitTotal credit=$baseCreditTotal',
    });
    await txn.insert('sync_queue', {
      'entity': 'voucher',
      'entity_id': id,
      'operation': 'upsert',
      'created_at': DateTime.now().toIso8601String(),
      'idempotency_key': 'voucher-$id',
      'remote_version': 0,
    });
    return id;
  }

  Future<void> _validatePostingAccounts(
    Transaction txn,
    Voucher voucher,
  ) async {
    final accountIds = voucher.lines.map((line) => line.accountId).toList();
    if (accountIds.any((id) => id == null || id <= 0)) {
      throw StateError('كل سطر ترحيل يجب أن يرتبط بحساب صالح');
    }
    await _validateAccountIds(txn, accountIds.whereType<int>().toList());
    final accountRows = await txn.query(
      'accounts',
      columns: ['id', 'is_group'],
      where: 'id IN (${List.filled(accountIds.length, '?').join(',')})',
      whereArgs: accountIds.whereType<int>().toList(),
    );
    if (accountRows.any((row) => (row['is_group'] as int? ?? 0) == 1)) {
      throw StateError('لا يمكن ترحيل سند إلى حساب تجميعي');
    }
    final uniqueIds = accountIds.whereType<int>().toSet();
    if (uniqueIds.length != accountIds.length) {
      throw StateError('لا يمكن ترحيل قيد بحساب مدين ودائن متماثل');
    }
    for (final line in voucher.lines) {
      final party = line.partyName;
      if (party != null && party.trim().isEmpty) {
        throw StateError('اسم الطرف المرتبط بالقيد غير صالح');
      }
    }
  }

  Future<void> _validateAccountIds(
    Transaction txn,
    List<int> accountIds,
  ) async {
    if (accountIds.any((id) => id <= 0) || accountIds.toSet().length != accountIds.length) {
      throw StateError('الحسابات المدينة والدائنة يجب أن تكون مختلفة وصالحة');
    }
    final uniqueIds = accountIds.toSet();
    final placeholders = List.filled(uniqueIds.length, '?').join(',');
    final rows = await txn.query(
      'accounts',
      columns: ['id'],
      where: 'active = 1 AND id IN ($placeholders)',
      whereArgs: uniqueIds.toList(),
    );
    final activeIds = rows.map((row) => row['id'] as int).toSet();
    if (activeIds.length != uniqueIds.length) {
      throw StateError('لا يمكن الترحيل إلى حساب غير موجود أو غير نشط');
    }
  }

  Future<void> _validatePostingCurrencies(
    Transaction txn,
    Voucher voucher,
  ) async {
    for (final line in voucher.lines) {
      await _validateAccountCurrencyIds(
        txn,
        [line.accountId!],
        _lineCurrency(voucher, line),
      );
    }
  }

  String _lineCurrency(Voucher voucher, VoucherLine line) =>
      (line.currency ?? voucher.currency).trim().toUpperCase();

  Future<void> _validateAccountCurrencyIds(
    Transaction txn,
    Iterable<int> ids,
    String rawCurrency,
  ) async {
    final currency = rawCurrency.trim().toUpperCase();
    final accountIds = ids.toSet();
    for (final accountId in accountIds) {
      final rows = await txn.query(
        'account_currencies',
        columns: ['currency'],
        where: 'account_id = ? AND currency = ?',
        whereArgs: [accountId, currency],
        limit: 1,
      );
      if (rows.isNotEmpty) continue;
      final account = await txn.query(
        'accounts',
        columns: ['currency'],
        where: 'id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      if (account.isEmpty || account.single['currency'] != currency) {
        throw StateError('العملة $currency غير مسموحة للحساب رقم $accountId');
      );
    }
  }

  Future<void> _validatePartyLinks(Transaction txn, Voucher voucher) async {
    for (final line in voucher.lines) {
      final partyId = line.partyId;
      if (partyId == null) continue;
      final rows = await txn.query(
        'parties',
        columns: ['account_id', 'active'],
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (rows.isEmpty || (rows.single['active'] as int? ?? 0) != 1) {
        throw StateError('الطرف المرتبط غير موجود أو غير نشط');
      }
      if (rows.single['account_id'] as int? != line.accountId) {
        throw StateError('الحساب التحليلي للطرف لا يطابق حساب القيد');
      }
    }
  }

  Future<List<Voucher>> vouchers() async {
    final db = await _db;
    final rows = await db.query('vouchers', orderBy: 'date DESC');
    return Future.wait(rows.map((row) async {
      final lineRows = await db.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      return Voucher(
            id: row['id'] as int?,
            number: row['number']! as String,
            type: VoucherType.values.firstWhere(
              (v) => v.name == row['type'],
              orElse: () => VoucherType.journal,
            ),
            description: row['description']! as String,
            amount: (row['amount']! as num).toDouble(),
            currency: row['currency']! as String,
            date: DateTime.parse(row['date']! as String),
            recipientName: row['recipient_name'] as String?,
            payerName: row['payer_name'] as String?,
            debitAccountId: row['debit_account_id'] as int?,
            creditAccountId: row['credit_account_id'] as int?,
            lines: lineRows.map((line) => VoucherLine(
              accountId: line['account_id'] as int?,
              partyId: line['party_id'] as int?,
              accountName: line['account_name']! as String,
              debit: (line['debit']! as num).toDouble(),
              credit: (line['credit']! as num).toDouble(),
              currency: line['currency'] as String?,
              partyName: line['party_name'] as String?,
            )).toList(growable: false),
          );
    }));
  }

  Future<int> upsertAccount(Account account) => LocalDatabase.instance.write(
        (db) async {
          final code = account.code.trim();
          if (code.isEmpty || account.name.trim().isEmpty) {
            throw ArgumentError('رقم واسم الحساب مطلوبان');
          }
          final duplicate = await db.query('accounts', columns: ['id'], where: 'code = ?', whereArgs: [code], limit: 1);
          if (duplicate.isNotEmpty && duplicate.first['id'] != account.id) {
            throw StateError('رقم الحساب مستخدم مسبقًا');
          }
          if (account.parentId != null) {
            if (account.parentId == account.id) {
              throw StateError('لا يمكن جعل الحساب أبًا لنفسه');
            }
            final parent = await db.query(
              'accounts',
              columns: ['id'],
              where: 'id = ? AND active = 1',
              whereArgs: [account.parentId],
              limit: 1,
            );
            if (parent.isEmpty) throw StateError('الحساب الأب غير موجود أو متوقف');
            await _ensureNoAccountCycle(
              db,
              accountId: account.id,
              parentId: account.parentId!,
            );
          }
          final primaryCurrency = account.currency.trim().toUpperCase();
          if (primaryCurrency.isEmpty) throw ArgumentError('عملة الحساب مطلوبة');
          final supported = <String>{
            primaryCurrency,
            ...account.supportedCurrencies
                .map((value) => value.trim().toUpperCase())
                .where((value) => value.isNotEmpty),
          };
          for (final currency in supported) {
            final active = await db.query(
              'currencies',
              columns: ['code'],
              where: 'code = ? AND active = 1',
              whereArgs: [currency],
              limit: 1,
            );
            if (active.isEmpty) throw StateError('العملة $currency غير نشطة أو غير معروفة');
          }
          final values = {
            'code': code,
            'name': account.name.trim(),
            'type': account.type,
            'kind': account.kind.name,
            'parent_id': account.parentId,
            'is_group': account.isGroup ? 1 : 0,
            'currency': primaryCurrency,
            'opening_balance': account.balance,
            'active': account.active ? 1 : 0,
          };
          final insertedId = account.id == null
              ? await db.insert('accounts', values)
              : account.id!;
          if (account.id != null) {
            final updated = await db.update(
              'accounts',
              values,
              where: 'id = ?',
              whereArgs: [account.id],
            );
            if (updated == 0) throw StateError('الحساب غير موجود');
          }
          await db.delete(
            'account_currencies',
            where: 'account_id = ?',
            whereArgs: [insertedId],
          );
          for (final currency in supported) {
            await db.insert('account_currencies', {
              'account_id': insertedId,
              'currency': currency,
              'is_primary': currency == primaryCurrency ? 1 : 0,
            });
          }
          return insertedId;
        },
      );

  Future<void> _ensureNoAccountCycle(
    Database db, {
    required int? accountId,
    required int parentId,
  }) async {
    if (accountId == null) return;
    final visited = <int>{accountId};
    var current = parentId;
    while (true) {
      if (!visited.add(current)) {
        throw StateError('لا يمكن إنشاء دورة في شجرة الحسابات');
      }
      final rows = await db.query(
        'accounts',
        columns: ['parent_id'],
        where: 'id = ?',
        whereArgs: [current],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['parent_id'] == null) return;
      current = rows.single['parent_id']! as int;
    }
  }
  Future<List<Account>> accounts({bool includeInactive = false}) async {
    final rows = await (await _db).query(
      'accounts',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'code ASC',
    );
    final accounts = rows
        .map(
          (r) => Account(
            id: r['id'] as int,
            code: r['code']! as String,
            name: r['name']! as String,
            type: r['type']! as String,
            kind: AccountKind.values.firstWhere(
              (k) => k.name == r['kind'],
              orElse: () => AccountKind.asset,
            ),
            parentId: r['parent_id'] as int?,
            isGroup: (r['is_group'] as int) == 1,
            currency: r['currency']! as String,
            balance: (r['opening_balance']! as num).toDouble(),
            active: (r['active'] as int? ?? 1) == 1,
          ),
        )
        .toList();
    for (var index = 0; index < accounts.length; index++) {
      final currencies = await _accountCurrencies(accounts[index].id!);
      if (currencies.isNotEmpty) {
        accounts[index] = accounts[index].withCurrencies(currencies);
      }
    }
    return accounts;
  }

  Future<List<String>> _accountCurrencies(int accountId) async {
    final rows = await (await _db).query(
      'account_currencies',
      columns: ['currency'],
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'is_primary DESC, currency ASC',
    );
    return rows.map((row) => row['currency']! as String).toList(growable: false);
  }

  Future<int?> accountIdByName(String name) async {
    final rows = await (await _db).query(
      'accounts',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<Account?> accountByCode(String code) async {
    final rows = await (await _db)
        .query('accounts', where: 'code = ?', whereArgs: [code], limit: 1);
    if (rows.isEmpty) return null;
    final account = _accountFromRow(rows.first);
    final currencies = await _accountCurrencies(account.id!);
    return currencies.isEmpty ? account : account.withCurrencies(currencies);
  }

  Future<int> ensureAccount(Account account) async {
    final existing = await accountByCode(account.code);
    if (existing?.id != null) return existing!.id!;
    return upsertAccount(account);
  }

  Account _accountFromRow(Map<String, Object?> row) => Account(
        id: row['id'] as int,
        code: row['code']! as String,
        name: row['name']! as String,
        type: row['type']! as String,
        kind: AccountKind.values.firstWhere((kind) => kind.name == row['kind'],
            orElse: () => AccountKind.asset),
        parentId: row['parent_id'] as int?,
        isGroup: (row['is_group'] as int) == 1,
        currency: row['currency']! as String,
        balance: (row['opening_balance']! as num).toDouble(),
        active: (row['active'] as int? ?? 1) == 1,
      );

  Future<void> setAccountActive(int id, bool active) => LocalDatabase.instance.write((db) async {
        if (!active) {
          final children = await db.query('accounts', columns: ['id'], where: 'parent_id = ? AND active = 1', whereArgs: [id], limit: 1);
          if (children.isNotEmpty) throw StateError('لا يمكن إيقاف حساب له حسابات فرعية نشطة');
        }
        await db.update('accounts', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
      });

  Future<int> insertParty(Party party) => upsertParty(party);

  Future<int> upsertParty(Party party) => LocalDatabase.instance.write(
        (db) async {
          final name = party.name.trim();
          final type = party.type.trim().toLowerCase();
          final currency = party.currency.trim().toUpperCase();
          if (name.length < 2 || !{'customer', 'supplier'}.contains(type)) {
            throw ArgumentError('اسم الطرف ونوعه مطلوبان');
          }
          final currencyRows = await db.query(
            'currencies',
            columns: ['code'],
            where: 'code = ? AND active = 1',
            whereArgs: [currency],
            limit: 1,
          );
          if (currencyRows.isEmpty) {
            throw StateError('العملة المختارة غير نشطة أو غير معروفة');
          }
          if (party.accountId == null) {
            throw StateError('يجب ربط الطرف بحساب تحليلي قبل الحفظ');
          }
          final accountRows = await db.query(
            'accounts',
            columns: ['kind', 'active', 'is_group'],
            where: 'id = ?',
            whereArgs: [party.accountId],
            limit: 1,
          );
          final account = accountRows.isEmpty ? null : accountRows.single;
          if (account == null ||
              (account['active'] as int? ?? 0) != 1 ||
              (account['is_group'] as int? ?? 1) == 1 ||
              account['kind'] != type) {
            throw StateError('اختر حسابًا تحليليًا نشطًا من نفس نوع الطرف');
          }
          final duplicate = await db.query(
            'parties',
            columns: ['id'],
            where: 'name = ? AND type = ? AND id != ?',
            whereArgs: [name, type, party.id ?? -1],
            limit: 1,
          );
          if (duplicate.isNotEmpty) {
            throw StateError('يوجد طرف بالاسم والنوع نفسيهما');
          }
          final values = {
            'account_id': party.accountId,
            'name': name,
            'type': type,
            'phone': party.phone?.trim().isEmpty == true
                ? null
                : party.phone?.trim(),
            'email': party.email?.trim().isEmpty == true
                ? null
                : party.email?.trim(),
            'currency': currency,
            'active': party.active ? 1 : 0,
          };
          if (party.id == null) return db.insert('parties', values);
          final updated = await db.update(
            'parties',
            values,
            where: 'id = ?',
            whereArgs: [party.id],
          );
          if (updated == 0) throw StateError('الطرف غير موجود');
          return party.id!;
        },
      );
  Future<List<Party>> parties({String? type}) async {
    final rows = await (await _db).query(
      'parties',
      where: type == null ? 'active = 1' : 'active = 1 AND type = ?',
      whereArgs: type == null ? null : [type],
      orderBy: 'name ASC',
    );
    return rows
        .map(
          (r) => Party(
            id: r['id'] as int,
            accountId: r['account_id'] as int?,
            name: r['name']! as String,
            type: r['type']! as String,
            phone: r['phone'] as String?,
            email: r['email'] as String?,
            currency: r['currency']! as String,
            active: (r['active'] as int? ?? 1) == 1,
          ),
        )
        .toList();
  }

  Future<void> saveCompany(CompanyProfile profile) =>
      LocalDatabase.instance.write((db) async {
        await db.insert(
            'company_profile',
            {
              'id': 1,
              'name': profile.name,
              'legal_name': profile.legalName,
              'tax_number': profile.taxNumber,
              'phone': profile.phone,
              'email': profile.email,
              'address': profile.address,
              'base_currency': profile.baseCurrency,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
  Future<CompanyProfile?> company() async {
    final rows = await (await _db).query('company_profile', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CompanyProfile(
      name: r['name']! as String,
      legalName: r['legal_name'] as String?,
      taxNumber: r['tax_number'] as String?,
      phone: r['phone'] as String?,
      email: r['email'] as String?,
      address: r['address'] as String?,
      baseCurrency: r['base_currency']! as String,
    );
  }

  Future<FinancialSummary> summary() async {
    final db = await _db;
    final totals = await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) debits, COALESCE(SUM(credit),0) credits FROM voucher_lines',
    );
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM vouchers'),
        ) ??
        0;
    final cash = await db.rawQuery('''
      SELECT COALESCE(SUM(a.opening_balance + COALESCE(j.debit, 0) - COALESCE(j.credit, 0)), 0) total
      FROM accounts a
      LEFT JOIN (
        SELECT jl.account_id, SUM(jl.debit) debit, SUM(jl.credit) credit
        FROM journal_lines jl
        GROUP BY jl.account_id
      ) j ON j.account_id = a.id
      WHERE a.kind = 'cash' AND a.active = 1 AND a.is_group = 0
    ''');
    final bank = await db.rawQuery('''
      SELECT COALESCE(SUM(a.opening_balance + COALESCE(j.debit, 0) - COALESCE(j.credit, 0)), 0) total
      FROM accounts a
      LEFT JOIN (
        SELECT jl.account_id, SUM(jl.debit) debit, SUM(jl.credit) credit
        FROM journal_lines jl
        GROUP BY jl.account_id
      ) j ON j.account_id = a.id
      WHERE a.kind = 'bank' AND a.active = 1 AND a.is_group = 0
    ''');
    return FinancialSummary(
      totalDebits: (totals.first['debits'] as num).toDouble(),
      totalCredits: (totals.first['credits'] as num).toDouble(),
      vouchersCount: count,
      cashBalance: (cash.first['total'] as num).toDouble(),
      bankBalance: (bank.first['total'] as num).toDouble(),
    );
  }

  Future<void> seedDemoAccountsForDevelopment({
    required bool explicitlyEnabled,
  }) async {
    if (!kDebugMode || !explicitlyEnabled) {
      throw StateError('بيانات العرض متاحة بتفعيل صريح في وضع التطوير فقط');
    }
    final existing = await (await _db).rawQuery(
      'SELECT COUNT(*) count FROM accounts WHERE is_group = 0',
    );
    if ((existing.first['count'] as int) > 0) {
      throw StateError('لا تُضاف بيانات العرض إلى دليل يحتوي حسابات فعلية');
    }
    for (final account in demoAccounts) {
      await upsertAccount(account);
    }
  }

  Future<void> log(String action, String details) =>
      LocalDatabase.instance.write((db) async {
        await db.insert('audit_log', {
          'created_at': DateTime.now().toIso8601String(),
          'action': action,
          'details': details,
        });
      });
  Future<List<AuditRecord>> audit() async {
    final rows = await (await _db).query(
      'audit_log',
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => AuditRecord(
            id: row['id'] as int?,
            createdAt: DateTime.parse(row['created_at']! as String),
            action: row['action']! as String,
            details: row['details']! as String,
          ),
        )
        .toList();
  }

  Future<int> pendingSyncCount() async =>
      Sqflite.firstIntValue(
        await (await _db).rawQuery(
          'SELECT COUNT(*) FROM sync_queue WHERE synced = 0',
        ),
      ) ??
      0;
  Future<List<Map<String, Object?>>> pendingSyncEnvelope() async =>
      (await _db).query('sync_queue', where: 'synced = 0', orderBy: 'id ASC');
  Future<void> markSynced(Iterable<int> ids) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          for (final id in ids) {
            await txn.update(
              'sync_queue',
              {'synced': 1},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        });
      });
  Future<void> recordConflict({
    required String entity,
    required int entityId,
    required String localHash,
    required String remoteHash,
  }) async =>
      log(
        'sync_conflict',
        '$entity:$entityId local=$localHash remote=$remoteHash',
      );

  Future<List<Remittance>> searchRemittances({
    String query = '',
    DateTime? from,
    DateTime? to,
    String? source,
  }) async {
    final args = <Object?>[];
    final where = <String>[];
    if (query.trim().isNotEmpty) {
      where.add(
        '(sender LIKE ? OR phone LIKE ? OR reference LIKE ? OR message LIKE ?)',
      );
      final q = '%${query.trim()}%';
      args.addAll([q, q, q, q]);
    }
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('created_at <= ?');
      args.add(to.toIso8601String());
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final rows = await (await _db).query(
      'remittances',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Remittance.fromMap).toList();
  }

  Future<void> saveConnector(ConnectorSettings settings) =>
      LocalDatabase.instance.write((db) async {
        await db.insert(
            'connector_configs',
            {
              'provider': settings.provider,
              'display_name': settings.displayName,
              'enabled': settings.enabled ? 1 : 0,
              'endpoint': settings.endpoint,
              'qr_payload': settings.qrPayload,
              'linked_account_id': settings.linkedAccountId,
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<int?> importBankSandboxTransaction({
    required int linkedAccountId,
    required BankSandboxTransaction transaction,
  }) =>
      LocalDatabase.instance.write((db) async {
        final existing = await db.query(
          'bank_transactions',
          columns: ['id'],
          where: 'provider = ? AND external_id = ?',
          whereArgs: ['bank_sandbox', transaction.externalId],
          limit: 1,
        );
        if (existing.isNotEmpty) return null;
        return db.insert('bank_transactions', {
          'provider': 'bank_sandbox',
          'external_id': transaction.externalId,
          'linked_account_id': linkedAccountId,
          'amount': transaction.amount,
          'currency': transaction.currency.trim().toUpperCase(),
          'direction': transaction.direction,
          'booked_at': transaction.bookedAt.toIso8601String(),
          'description': transaction.description.trim(),
          'imported_at': DateTime.now().toIso8601String(),
          'status': 'imported',
        });
      });

  Future<List<Map<String, Object?>>> bankSandboxTransactions() async =>
      (await _db).query(
        'bank_transactions',
        where: 'provider = ?',
        whereArgs: ['bank_sandbox'],
        orderBy: 'booked_at DESC, id DESC',
      );

  Future<int?> voucherIdByNumber(String number) async {
    final rows = await (await _db).query(
      'vouchers',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [number.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id'] as int;
  }

  Future<void> markBankSandboxPosted({
    required int id,
    required int voucherId,
  }) =>
      LocalDatabase.instance.write((db) async {
        await db.update(
          'bank_transactions',
          {'status': 'posted', 'posted_voucher_id': voucherId},
          where: 'id = ? AND status = ?',
          whereArgs: [id, 'imported'],
        );
      });

  Future<List<ConnectorSettings>> connectors() async {
    final rows = await (await _db).query(
      'connector_configs',
      orderBy: 'display_name ASC',
    );
    return rows
        .map(
          (r) => ConnectorSettings(
            provider: r['provider']! as String,
            displayName: r['display_name']! as String,
            enabled: (r['enabled'] as int) == 1,
            endpoint: r['endpoint'] as String?,
            qrPayload: r['qr_payload'] as String?,
            linkedAccountId: r['linked_account_id'] as int?,
          ),
        )
        .toList();
  }

  Future<int> addIncomingMessage(IncomingMessage message) =>
      LocalDatabase.instance.write(
        (db) => db.insert('incoming_messages', {
          'provider': message.provider,
          'sender': message.sender,
          'sender_phone': message.senderPhone,
          'body': message.body,
          'received_at': message.receivedAt.toIso8601String(),
          'archived': message.archived ? 1 : 0,
          'parsed_amount': message.parsedAmount,
          'parsed_currency': message.parsedCurrency,
          'reference': message.reference,
        }),
      );
  Future<List<IncomingMessage>> incomingMessages({
    bool archived = false,
  }) async {
    final rows = await (await _db).query(
      'incoming_messages',
      where: 'archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'received_at DESC',
    );
    return rows
        .map(
          (r) => IncomingMessage(
            id: r['id'] as int,
            provider: r['provider']! as String,
            sender: r['sender']! as String,
            senderPhone: r['sender_phone'] as String?,
            body: r['body']! as String,
            receivedAt: DateTime.parse(r['received_at']! as String),
            archived: (r['archived'] as int) == 1,
            parsedAmount: (r['parsed_amount'] as num?)?.toDouble(),
            parsedCurrency: r['parsed_currency'] as String?,
            reference: r['reference'] as String?,
          ),
        )
        .toList();
  }

  Future<void> archiveIncomingMessage(int id) =>
      LocalDatabase.instance.write((db) async {
        await db.update(
          'incoming_messages',
          {'archived': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await db.insert('audit_log', {
          'created_at': DateTime.now().toIso8601String(),
          'action': 'archive_message',
          'details': 'message=$id',
        });
      });

  Future<List<JournalEntry>> journalEntries({String query = ''}) async {
    final trimmed = query.trim();
    final rows = await (await _db).query(
      'journal_entries',
      where: trimmed.isEmpty ? null : '(number LIKE ? OR description LIKE ?)',
      whereArgs: trimmed.isEmpty ? null : ['%$trimmed%', '%$trimmed%'],
      orderBy: 'entry_date DESC, id DESC',
    );
    return rows.map(JournalEntry.fromMap).toList(growable: false);
  }
}
