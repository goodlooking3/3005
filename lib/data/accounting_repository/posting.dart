part of '../accounting_repository.dart';

extension AccountingRepositoryPosting on AccountingRepository {
  Future<int> insertSalesJournal(
    Transaction txn, {
    required String number,
    required String description,
    required double amount,
    required String currency,
    required DateTime date,
    required int cashAccountId,
    required int salesAccountId,
    required int partyId,
    required String paymentAccount,
    required String customerName,
  }) async {
    await AccountingAuthorization.instance
        .require(txn, AccountingPermission.postVouchers);
    if (!amount.isFinite ||
        amount <= 0 ||
        number.trim().isEmpty ||
        currency.trim().isEmpty ||
        paymentAccount.trim().isEmpty) {
      throw ArgumentError('بيانات قيد البيع غير صالحة');
    }
    await _validateAccountIds(txn, [cashAccountId, salesAccountId]);
    await _validateAccountCurrencyIds(
        txn, [cashAccountId, salesAccountId], currency);
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
        'party_id': partyId,
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
        'base_debit':
            (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit':
            (line['credit'] as num).toDouble() * valuation.exchangeRate,
      });
      await txn.insert('journal_lines', {
        'journal_entry_id': journalId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit':
            (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit':
            (line['credit'] as num).toDouble() * valuation.exchangeRate,
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
    required int partyId,
    required String paymentAccount,
    required String customerName,
    required String source,
  }) async {
    await AccountingAuthorization.instance
        .require(txn, AccountingPermission.reverseVouchers);
    if (!amount.isFinite || amount <= 0 || number.trim().isEmpty) {
      throw ArgumentError('بيانات القيد العكسي غير صالحة');
    }
    await _validateAccountIds(txn, [salesAccountId, cashAccountId]);
    await _validateAccountCurrencyIds(
        txn, [salesAccountId, cashAccountId], currency);
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
        'party_id': partyId,
        'party_name': customerName
      },
    ];
    for (final line in lines) {
      await txn.insert('voucher_lines', {
        'voucher_id': voucherId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit':
            (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit':
            (line['credit'] as num).toDouble() * valuation.exchangeRate,
      });
      await txn.insert('journal_lines', {
        'journal_entry_id': journalId,
        ...line,
        'currency': currency.trim().toUpperCase(),
        'base_debit':
            (line['debit'] as num).toDouble() * valuation.exchangeRate,
        'base_credit':
            (line['credit'] as num).toDouble() * valuation.exchangeRate,
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
    await AccountingAuthorization.instance
        .require(txn, AccountingPermission.postVouchers);
    if (!voucher.amount.isFinite || voucher.amount <= 0) {
      throw ArgumentError('Voucher amount must be positive');
    }
    if (!voucher.isBalanced) {
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
      where: 'number = ? COLLATE NOCASE',
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
          (total, entry) =>
              total +
              entry.value.debit * lineValuations[entry.key].exchangeRate,
        );
    final baseCreditTotal = voucher.lines.asMap().entries.fold<double>(
          0,
          (total, entry) =>
              total +
              entry.value.credit * lineValuations[entry.key].exchangeRate,
        );
    if ((baseDebitTotal - baseCreditTotal).abs() > 0.000001 ||
        (baseDebitTotal - valuation.baseAmount).abs() > 0.000001) {
      throw ArgumentError(
          'يجب توازن المدين والدائن بعد تحويلهما إلى العملة الأساسية');
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
    await AuditRepository.instance.recordOn(
      txn,
      action: 'create_voucher',
      entityType: 'voucher',
      entityId: '$id',
      details:
          '${voucher.type.name}:${voucher.number} amount=${voucher.amount}',
    );
    await AuditRepository.instance.recordOn(
      txn,
      action: 'post_journal_entry',
      entityType: 'journal_entry',
      entityId: '$journalId',
      details: 'voucher=$id debit=$baseDebitTotal credit=$baseCreditTotal',
    );
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
      columns: ['id', 'is_group', 'kind'],
      where: 'id IN (${List.filled(accountIds.length, '?').join(',')})',
      whereArgs: accountIds.whereType<int>().toList(),
    );
    if (accountRows.any((row) => (row['is_group'] as int? ?? 0) == 1)) {
      throw StateError('لا يمكن ترحيل سند إلى حساب تجميعي');
    }
    final kinds = {
      for (final row in accountRows) row['id'] as int: row['kind'] as String,
    };
    final debitCashOrBank = voucher.lines.any((line) =>
        line.debit > 0 && {'cash', 'bank'}.contains(kinds[line.accountId]));
    final creditCashOrBank = voucher.lines.any((line) =>
        line.credit > 0 && {'cash', 'bank'}.contains(kinds[line.accountId]));
    if (voucher.type == VoucherType.receipt && !debitCashOrBank) {
      throw StateError('سند القبض يجب أن يخصم حساب صندوق أو بنك');
    }
    if (voucher.type == VoucherType.payment && !creditCashOrBank) {
      throw StateError(
          'سند الصرف يجب أن يضيف حساب صندوق أو بنك إلى الطرف الدائن');
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
    if (accountIds.any((id) => id <= 0) ||
        accountIds.toSet().length != accountIds.length) {
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
      }
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
      if ((rows.single['account_id'] as int?) != line.accountId) {
        throw StateError('الحساب التحليلي للطرف لا يطابق حساب القيد');
      }
    }
  }
}
