part of '../accounting_repository.dart';

extension AccountingRepositoryBalances on AccountingRepository {
  /// Recomputes posted balances from the immutable journal, never from cached totals.
  Future<List<AccountBalance>> accountBalances({
    DateTime? asOf,
    bool includeInactive = false,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final baseCurrency = await currencyPolicy.requireBaseCurrency(db);
    final cutoff = asOf?.toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT
        a.id AS account_id,
        a.code AS account_code,
        a.name AS account_name,
        a.kind AS account_kind,
        a.is_group AS is_group,
        a.currency AS primary_currency,
        a.opening_balance AS opening_balance,
        COALESCE(ac.currency, a.currency) AS currency,
        COALESCE(SUM(jl.debit), 0) AS debit_total,
        COALESCE(SUM(jl.credit), 0) AS credit_total,
        COALESCE(SUM(COALESCE(jl.base_debit, jl.debit)), 0) AS base_debit_total,
        COALESCE(SUM(COALESCE(jl.base_credit, jl.credit)), 0) AS base_credit_total,
        SUM(CASE WHEN jl.id IS NOT NULL AND
          (jl.base_debit IS NULL OR jl.base_credit IS NULL) THEN 1 ELSE 0 END)
          AS missing_base_count
      FROM accounts a
      LEFT JOIN account_currencies ac ON ac.account_id = a.id
      LEFT JOIN (
        SELECT jl.*, je.entry_date
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.journal_entry_id
      ) jl ON jl.account_id = a.id
        AND UPPER(COALESCE(jl.currency, a.currency)) =
            UPPER(COALESCE(ac.currency, a.currency))
        AND (? IS NULL OR jl.entry_date <= ?)
      WHERE (? = 1 OR a.active = 1)
      GROUP BY a.id, COALESCE(ac.currency, a.currency)
      ORDER BY a.code ASC, COALESCE(ac.currency, a.currency) ASC
      ''',
      [cutoff, cutoff, includeInactive ? 1 : 0],
    );

    return rows.map((row) {
      final currency = (row['currency']! as String).toUpperCase();
      final primaryCurrency =
          (row['primary_currency']! as String).toUpperCase();
      final opening = (row['opening_balance']! as num).toDouble();
      final debit = (row['debit_total']! as num).toDouble();
      final credit = (row['credit_total']! as num).toDouble();
      final missingBase = (row['missing_base_count'] as num? ?? 0).toInt() > 0;
      final baseDebit = (missingBase && currency != baseCurrency)
          ? null
          : (row['base_debit_total']! as num).toDouble();
      final baseCredit = (missingBase && currency != baseCurrency)
          ? null
          : (row['base_credit_total']! as num).toDouble();
      final currencyOpening = currency == primaryCurrency ? opening : 0.0;
      final baseOpening = currency != baseCurrency && currencyOpening != 0
          ? null
          : currencyOpening;
      return AccountBalance(
        accountId: row['account_id']! as int,
        accountCode: row['account_code']! as String,
        accountName: row['account_name']! as String,
        kind: AccountKind.values.firstWhere(
          (kind) => kind.name == row['account_kind'],
          orElse: () => AccountKind.asset,
        ),
        isGroup: (row['is_group'] as int? ?? 0) == 1,
        currency: currency,
        openingBalance: currencyOpening,
        debitTotal: debit,
        creditTotal: credit,
        baseDebitTotal: baseDebit,
        baseCreditTotal: baseCredit,
        openingBalanceInBaseCurrency: baseOpening,
      );
    }).toList(growable: false);
  }
}
