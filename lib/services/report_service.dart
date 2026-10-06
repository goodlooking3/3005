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

  const CashFlowRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.direction,
  });
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
    final filter = _filters(
      currency: currency,
      from: from,
      to: to,
      dateColumn: 'je.entry_date',
      currencyColumn: 'l.currency',
    );
    final debit = _amount('l', 'debit', useBase: currency == null);
    final credit = _amount('l', 'credit', useBase: currency == null);
    final where =
        filter.where.isEmpty ? '' : ' AND ${filter.where.substring(6)}';
    if (currency == null) await _ensureBaseValuations(db, filter);
    final rows = await db.rawQuery(
      '''SELECT je.entry_date date, je.description,
        CASE WHEN $debit > 0 THEN $debit ELSE $credit END amount,
        CASE WHEN $debit > 0 THEN 'in' ELSE 'out' END direction
      FROM journal_lines l
      JOIN journal_entries je ON je.id = l.journal_entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE a.kind IN ('cash','bank')$where
      ORDER BY je.entry_date ASC, je.id ASC, l.id ASC''',
      filter.args,
    );
    return rows
        .map(
          (row) => CashFlowRow(
            date: row['date']! as String,
            description: row['description']! as String,
            amount: (row['amount'] as num).toDouble(),
            direction: row['direction']! as String,
          ),
        )
        .toList();
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
