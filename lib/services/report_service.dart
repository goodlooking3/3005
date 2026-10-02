import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';

class LedgerRow {
  final String date;
  final String account;
  final String description;
  final double debit;
  final double credit;
  const LedgerRow({required this.date, required this.account, required this.description, required this.debit, required this.credit});
}

class TrialBalanceRow {
  final String code;
  final String account;
  final double debit;
  final double credit;
  const TrialBalanceRow({required this.code, required this.account, required this.debit, required this.credit});
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
  const CashFlowRow({required this.date, required this.description, required this.amount, required this.direction});
}

class ReportService {
  Future<Database> get _db => LocalDatabase.instance.database;

  Future<List<LedgerRow>> generalLedger({DateTime? from, DateTime? to, int? accountId, String? currency}) async {
    final db = await _db;
    final filter = _filters(currency: currency, from: from, to: to, accountId: accountId, accountColumn: 'l.account_id', prefix: 'v.');
    final rows = await db.rawQuery(
      'SELECT v.date, l.account_name account, v.description, l.debit, l.credit FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id ${filter.where} ORDER BY v.date ASC',
      filter.args,
    );
    return rows.map((r) => LedgerRow(date: r['date']! as String, account: r['account']! as String, description: r['description']! as String, debit: (r['debit'] as num).toDouble(), credit: (r['credit'] as num).toDouble())).toList();
  }

  Future<List<TrialBalanceRow>> trialBalance({String? currency, DateTime? from, DateTime? to}) async {
    final db = await _db;
    final filter = _filters(currency: currency, from: from, to: to, prefix: 'v.');
    final rows = await db.rawQuery(
      'SELECT a.code, a.name account, COALESCE(SUM(l.debit),0) debit, COALESCE(SUM(l.credit),0) credit FROM accounts a LEFT JOIN voucher_lines l ON l.account_id = a.id LEFT JOIN vouchers v ON v.id = l.voucher_id ${filter.where} GROUP BY a.id, a.code, a.name ORDER BY a.code',
      filter.args,
    );
    return rows.map((r) => TrialBalanceRow(code: r['code']! as String, account: r['account']! as String, debit: (r['debit'] as num).toDouble(), credit: (r['credit'] as num).toDouble())).toList();
  }

  Future<ProfitLossReport> profitAndLoss({String? currency, DateTime? from, DateTime? to}) async {
    final db = await _db;
    final filter = _filters(currency: currency, from: from, to: to, prefix: 'v.');
    final join = ' JOIN vouchers v ON v.id = l.voucher_id';
    final revenue = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE WHEN l.credit > 0 THEN l.credit ELSE 0 END),0) total FROM voucher_lines l JOIN accounts a ON a.id = l.account_id$join WHERE a.kind = 'revenue'${filter.where.isEmpty ? '' : ' AND ${filter.where.substring(6)}'}",
      filter.args,
    );
    final expenses = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE WHEN l.debit > 0 THEN l.debit ELSE 0 END),0) total FROM voucher_lines l JOIN accounts a ON a.id = l.account_id$join WHERE a.kind = 'expense'${filter.where.isEmpty ? '' : ' AND ${filter.where.substring(6)}'}",
      filter.args,
    );
    return ProfitLossReport(revenue: (revenue.first['total'] as num).toDouble(), expenses: (expenses.first['total'] as num).toDouble());
  }

  Future<List<CashFlowRow>> cashFlow({String? currency, DateTime? from, DateTime? to}) async {
    final db = await _db;
    final filter = _filters(currency: currency, from: from, to: to, prefix: 'v.');
    final rows = await db.rawQuery(
      "SELECT v.date, v.description, CASE WHEN l.debit > 0 THEN l.debit ELSE l.credit END amount, CASE WHEN l.debit > 0 THEN 'in' ELSE 'out' END direction FROM voucher_lines l JOIN vouchers v ON v.id = l.voucher_id JOIN accounts a ON a.id = l.account_id WHERE a.kind IN ('cash','bank')${filter.where.isEmpty ? '' : ' AND ${filter.where.substring(6)}'} ORDER BY v.date ASC",
      filter.args,
    );
    return rows.map((r) => CashFlowRow(date: r['date']! as String, description: r['description']! as String, amount: (r['amount'] as num).toDouble(), direction: r['direction']! as String)).toList();
  }

  _ReportFilter _filters({String? currency, DateTime? from, DateTime? to, int? accountId, String prefix = '', String accountColumn = 'account_id'}) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (currency != null && currency.trim().isNotEmpty) {
      clauses.add('${prefix}currency = ?');
      args.add(currency.trim().toUpperCase());
    }
    if (from != null) {
      clauses.add('${prefix}date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      clauses.add('${prefix}date <= ?');
      args.add(to.toIso8601String());
    }
    if (accountId != null) {
      clauses.add('$accountColumn = ?');
      args.add(accountId);
    }
    return _ReportFilter(clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', args);
  }
}

class _ReportFilter {
  final String where;
  final List<Object?> args;
  const _ReportFilter(this.where, this.args);
}
