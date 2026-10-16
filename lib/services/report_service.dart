import 'package:sqflite/sqflite.dart';

import '../data/accounting_authorization.dart';
import '../data/accounting_policy_repository.dart';
import '../data/currency_policy.dart';
import '../data/local_database.dart';
import '../data/accounting_repository.dart';
import '../core/accounting.dart';

part 'report_service_balance_sheet.dart';
part 'report_service_party.dart';

class LedgerRow {
  final String date;
  final String account;
  final String description;
  final double debit;
  final double credit;

  const LedgerRow({
    required this.date,
    required this.account,
    required this.description,
    required this.debit,
    required this.credit,
  });
}

class TrialBalanceRow {
  final String code;
  final String account;
  final double debit;
  final double credit;

  const TrialBalanceRow({
    required this.code,
    required this.account,
    required this.debit,
    required this.credit,
  });
}

class ProfitLossReport {
  final double revenue;
  final double expenses;

  const ProfitLossReport({required this.revenue, required this.expenses});

  double get net => revenue - expenses;
}

class CashFlowRow {
  final String date;
  final String description;
  final double amount;
  final String direction;
  final String category;

  const CashFlowRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.direction,
    required this.category,
  });
}

class CashFlowReconciliation {
  final String currency;
  final double openingBalance;
  final double netLedgerMovement;
  final double endingBalance;
  final double difference;

  const CashFlowReconciliation({
    required this.currency,
    required this.openingBalance,
    required this.netLedgerMovement,
    required this.endingBalance,
    required this.difference,
  });

  bool get reconciled => difference.abs() <= 0.01;
}

class ReportService {
  Future<Database> get _db => LocalDatabase.instance.database;

  Future<List<LedgerRow>> generalLedger({
    DateTime? from,
    DateTime? to,
    int? accountId,
    String? currency,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final filter = _filters(
      currency: currency,
      from: from,
      to: to,
      accountId: accountId,
      dateColumn: 'je.entry_date',
      currencyColumn: 'l.currency',
      accountColumn: 'l.account_id',
    );
    if (currency == null) await _ensureBaseValuations(db, filter);
    final debit = _amount('l', 'debit', useBase: currency == null);
    final credit = _amount('l', 'credit', useBase: currency == null);
    final rows = await db.rawQuery(
      '''SELECT je.entry_date date, l.account_name account, je.description,
        $debit debit, $credit credit
      FROM journal_lines l
      JOIN journal_entries je ON je.id = l.journal_entry_id
      ${filter.where}
      ORDER BY je.entry_date ASC, je.id ASC, l.id ASC''',
      filter.args,
    );
    return rows
        .map(
          (row) => LedgerRow(
            date: row['date']! as String,
            account: row['account']! as String,
            description: row['description']! as String,
            debit: (row['debit'] as num).toDouble(),
            credit: (row['credit'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<TrialBalanceRow>> trialBalance({
    String? currency,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final filter = _filters(
      currency: currency,
      from: from,
      to: to,
      dateColumn: 'je.entry_date',
      currencyColumn: 'jl.currency',
    );
    if (currency == null) await _ensureBaseValuations(db, filter);
    final debit = _amount('jl', 'debit', useBase: currency == null);
    final credit = _amount('jl', 'credit', useBase: currency == null);
    final rows = await db.rawQuery(
      '''SELECT a.code, a.name account,
        COALESCE(ledger.debit, 0) debit, COALESCE(ledger.credit, 0) credit
      FROM accounts a
      LEFT JOIN (
        SELECT jl.account_id, SUM($debit) debit, SUM($credit) credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        ${filter.where}
        GROUP BY jl.account_id
      ) ledger ON ledger.account_id = a.id
      ORDER BY a.code''',
      filter.args,
    );
    return rows
        .map(
          (row) => TrialBalanceRow(
            code: row['code']! as String,
            account: row['account']! as String,
            debit: (row['debit'] as num).toDouble(),
            credit: (row['credit'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<ProfitLossReport> profitAndLoss({
    String? currency,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final filter = _filters(
      currency: currency,
      from: from,
      to: to,
      dateColumn: 'je.entry_date',
      currencyColumn: 'l.currency',
    );
    if (currency == null) await _ensureBaseValuations(db, filter);
    final debit = _amount('l', 'debit', useBase: currency == null);
    final credit = _amount('l', 'credit', useBase: currency == null);
    const join = '''FROM journal_lines l
      JOIN journal_entries je ON je.id = l.journal_entry_id
      JOIN accounts a ON a.id = l.account_id''';
    final where =
        filter.where.isEmpty ? '' : ' AND ${filter.where.substring(6)}';
    final revenue = await db.rawQuery(
      "SELECT COALESCE(SUM($credit - $debit),0) total "
      "$join WHERE a.kind = 'revenue'$where",
      filter.args,
    );
    final expenses = await db.rawQuery(
      "SELECT COALESCE(SUM($debit - $credit),0) total "
      "$join WHERE a.kind = 'expense'$where",
      filter.args,
    );
    return ProfitLossReport(
      revenue: (revenue.first['total'] as num).toDouble(),
      expenses: (expenses.first['total'] as num).toDouble(),
    );
  }

  Future<List<CashFlowRow>> cashFlow({
    String? currency,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final requestedCurrency = currency?.trim().toUpperCase();
    final selectedCurrency = requestedCurrency == null || requestedCurrency.isEmpty
        ? null
        : requestedCurrency;
    final filter = _filters(
      currency: selectedCurrency,
      from: from,
      to: to,
      dateColumn: 'je.entry_date',
      currencyColumn: 'cash.currency',
    );
    final debit =
        _amount('cash', 'debit', useBase: selectedCurrency == null);
    final credit =
        _amount('cash', 'credit', useBase: selectedCurrency == null);
    final where = filter.where;
    if (selectedCurrency == null) await _ensureBaseValuations(db, filter);
    final rows = await db.rawQuery(
      '''SELECT je.entry_date date, je.description,
        ABS(SUM($debit - $credit)) amount,
        CASE WHEN SUM($debit - $credit) > 0 THEN 'in' ELSE 'out' END direction,
        CASE WHEN COALESCE(counterpart.line_count, 0) = 0
          THEN 'internal_transfer'
          WHEN counterpart.category_count = 1 THEN counterpart.category
          ELSE 'unclassified' END category
      FROM journal_lines cash
      JOIN journal_entries je ON je.id = cash.journal_entry_id
      JOIN accounts cash_account ON cash_account.id = cash.account_id
      LEFT JOIN (
        SELECT jl.journal_entry_id,
          COUNT(*) line_count,
          COUNT(DISTINCT COALESCE(a.cash_flow_category, 'unclassified')) category_count,
          MIN(COALESCE(a.cash_flow_category, 'unclassified')) category
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.kind NOT IN ('cash', 'bank')
        GROUP BY jl.journal_entry_id
      ) counterpart ON counterpart.journal_entry_id = je.id
      ${where.isEmpty ? '' : where}
        ${where.isEmpty ? 'WHERE' : 'AND'} cash_account.kind IN ('cash','bank')
      GROUP BY je.id, cash_account.id, cash.currency, counterpart.line_count,
        counterpart.category_count, counterpart.category
      HAVING ABS(SUM($debit - $credit)) > 0.000001
      ORDER BY je.entry_date ASC, je.id ASC, cash_account.id ASC''',
      filter.args,
    );
    return rows
        .map(
          (row) => CashFlowRow(
            date: row['date']! as String,
            description: row['description']! as String,
            amount: (row['amount'] as num).toDouble(),
            direction: row['direction']! as String,
            category: row['category']! as String,
          ),
      )
        .toList();
  }

  /// Internal ledger reconciliation only; this is not an IAS 7 statement.
  Future<CashFlowReconciliation> cashFlowReconciliation({
    String? currency,
    DateTime? from,
    DateTime? to,
  }) async {
    if (from != null && to != null && to.isBefore(from)) {
      throw ArgumentError('نهاية فترة حركة النقد تسبق بدايتها');
    }
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final requestedCurrency = currency?.trim().toUpperCase();
    final selectedCurrency = requestedCurrency == null || requestedCurrency.isEmpty
        ? null
        : requestedCurrency;
    final baseCurrency = await currencyPolicy.requireBaseCurrency(db);
    final reportCurrency = selectedCurrency ?? baseCurrency;
    final openingCutoff = from == null
        ? DateTime(1)
        : DateTime(from.year, from.month, from.day)
            .subtract(const Duration(microseconds: 1));
    final endingCutoff = to ?? DateTime.now();

    Future<double> cashBalance(DateTime asOf) async {
      final balances = await AccountingRepository().accountBalances(
        asOf: asOf,
        includeInactive: true,
      );
      var total = 0.0;
      for (final balance in balances.where((item) =>
          !item.isGroup &&
          {AccountKind.cash, AccountKind.bank}.contains(item.kind) &&
          (selectedCurrency == null || item.currency == selectedCurrency))) {
        final amount = selectedCurrency == null
            ? balance.baseBalance
            : balance.balance;
        if (amount == null || !amount.isFinite) {
          throw StateError(
            'تعذر مصالحة حركة النقد: يوجد رصيد نقدي بلا تقييم للعملة الأساسية',
          );
        }
        total += amount;
      }
      return total;
    }

    final opening = await cashBalance(openingCutoff);
    final ending = await cashBalance(endingCutoff);
    final rows =
        await cashFlow(currency: selectedCurrency, from: from, to: to);
    final movement = rows.fold<double>(0, (sum, row) {
      final signed = row.direction == 'in' ? row.amount : -row.amount;
      return sum + signed;
    });
    return CashFlowReconciliation(
      currency: reportCurrency,
      openingBalance: opening,
      netLedgerMovement: movement,
      endingBalance: ending,
      difference: ending - opening - movement,
    );
  }

  String _amount(String alias, String column, {required bool useBase}) =>
      useBase
          ? 'COALESCE($alias.base_$column, $alias.$column)'
          : '$alias.$column';

  Future<void> _ensureBaseValuations(
    Database db,
    _ReportFilter filter,
  ) async {
    final baseCurrency = await currencyPolicy.requireBaseCurrency(db);
    final where = filter.where.isEmpty
        ? ''
        : ' AND ${filter.where.substring('WHERE '.length)}';
    final missing = await db.rawQuery(
      '''
      SELECT l.id FROM journal_lines l
      JOIN journal_entries je ON je.id = l.journal_entry_id
      WHERE UPPER(COALESCE(l.currency, ?)) != ?
        AND (l.base_debit IS NULL OR l.base_credit IS NULL)$where
      LIMIT 1
      ''',
      [baseCurrency, baseCurrency, ...filter.args],
    );
    if (missing.isNotEmpty) {
      throw StateError(
        'تعذر إنشاء تقرير بالعملة الأساسية؛ توجد أسطر أجنبية بلا تقييم محفوظ',
      );
    }
  }

  _ReportFilter _filters({
    String? currency,
    DateTime? from,
    DateTime? to,
    int? accountId,
    String dateColumn = 'entry_date',
    String currencyColumn = 'currency',
    String accountColumn = 'account_id',
  }) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (currency != null && currency.trim().isNotEmpty) {
      clauses.add('$currencyColumn = ?');
      args.add(currency.trim().toUpperCase());
    }
    if (from != null) {
      clauses.add('$dateColumn >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      clauses.add('$dateColumn <= ?');
      args.add(to.toIso8601String());
    }
    if (accountId != null) {
      clauses.add('$accountColumn = ?');
      args.add(accountId);
    }
    return _ReportFilter(
        clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', args);
  }
}

class _ReportFilter {
  final String where;
  final List<Object?> args;

  const _ReportFilter(this.where, this.args);
}
