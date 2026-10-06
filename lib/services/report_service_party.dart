part of 'report_service.dart';

class PartyAgingRow {
  final int partyId;
  final String partyName;
  final String currency;
  final double notDue;
  final double days0To30;
  final double days31To60;
  final double days61To90;
  final double daysOver90;
  final double unappliedCredit;

  const PartyAgingRow({
    required this.partyId,
    required this.partyName,
    required this.currency,
    required this.notDue,
    required this.days0To30,
    required this.days31To60,
    required this.days61To90,
    required this.daysOver90,
    required this.unappliedCredit,
  });

  double get openItems =>
      notDue + days0To30 + days31To60 + days61To90 + daysOver90;
  double get netBalance => openItems - unappliedCredit;
}

class AgingUnallocatedBalance {
  final String currency;
  final double balance;

  const AgingUnallocatedBalance(
      {required this.currency, required this.balance});
}

class PartyAgingReport {
  final String partyType;
  final DateTime asOf;
  final List<PartyAgingRow> rows;
  final List<AgingUnallocatedBalance> unallocated;

  const PartyAgingReport({
    required this.partyType,
    required this.asOf,
    required this.rows,
    required this.unallocated,
  });
}

class PartyStatementLine {
  final DateTime date;
  final String number;
  final String description;
  final String currency;
  final double debit;
  final double credit;
  final double balance;

  const PartyStatementLine({
    required this.date,
    required this.number,
    required this.description,
    required this.currency,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}

extension ReportServicePartyReports on ReportService {
  Future<PartyAgingReport> receivablesAging({
    required DateTime asOf,
    String? currency,
  }) =>
      _partyAging(
        partyType: 'customer',
        asOf: asOf,
        currency: currency,
      );

  Future<PartyAgingReport> payablesAging({
    required DateTime asOf,
    String? currency,
  }) =>
      _partyAging(
        partyType: 'supplier',
        asOf: asOf,
        currency: currency,
      );

  Future<PartyAgingReport> _partyAging({
    required String partyType,
    required DateTime asOf,
    String? currency,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final normalizedCurrency = currency?.trim().toUpperCase();
    final cutoff = _reportDayAfter(asOf).toIso8601String();
    final args = <Object?>[partyType, partyType, cutoff];
    var extra = '';
    if (normalizedCurrency != null && normalizedCurrency.isNotEmpty) {
      extra += ' AND UPPER(jl.currency) = ?';
      args.add(normalizedCurrency);
    }
    final entries = await db.rawQuery('''
      SELECT p.id party_id,
        COALESCE(NULLIF(trim(p.name_ar), ''), p.name) party_name,
        p.account_id, UPPER(jl.currency) currency,
        jl.debit, jl.credit, je.entry_date, je.due_date
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN parties p ON p.id = jl.party_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE lower(p.type) = ? AND a.kind = ?
        AND p.account_id = jl.account_id
        AND je.entry_date < ?$extra
      ORDER BY p.id, p.account_id, UPPER(jl.currency),
        je.entry_date, je.id, jl.id
    ''', args);

    final accumulators = <(int, int, String), _AgingAccumulator>{};
    for (final row in entries) {
      final id = row['party_id']! as int;
      final accountId = row['account_id']! as int;
      final money = row['currency']! as String;
      final key = (id, accountId, money);
      final accumulator = accumulators.putIfAbsent(
        key,
        () => _AgingAccumulator(
          partyId: id,
          partyName: row['party_name']! as String,
          currency: money,
        ),
      );
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();
      final signed = partyType == 'customer' ? debit - credit : credit - debit;
      accumulator.apply(
        DateTime.parse(row['entry_date']! as String),
        signed,
        dueDate: row['due_date'] == null
            ? null
            : DateTime.parse(row['due_date']! as String),
      );
    }

    final reportRows = accumulators.values
        .map((item) => item.finish(asOf))
        .where(
            (row) => row.openItems > 0.000001 || row.unappliedCredit > 0.000001)
        .toList()
      ..sort((a, b) => a.partyName.compareTo(b.partyName));
    final balances = await AccountingRepository()
        .accountBalances(asOf: _reportEndOfDay(asOf), includeInactive: true);
    final controlTotals = <String, double>{};
    for (final balance in balances.where((item) =>
        item.kind.name == partyType &&
        (normalizedCurrency == null || item.currency == normalizedCurrency))) {
      controlTotals.update(
        balance.currency,
        (amount) => amount + balance.balance,
        ifAbsent: () => balance.balance,
      );
    }
    final matchedByCurrency = <String, double>{};
    for (final row in reportRows) {
      matchedByCurrency.update(
        row.currency,
        (amount) => amount + row.netBalance,
        ifAbsent: () => row.netBalance,
      );
    }
    final currencies = {...controlTotals.keys, ...matchedByCurrency.keys};
    final unallocated = currencies
        .map((code) => AgingUnallocatedBalance(
              currency: code,
              balance:
                  (controlTotals[code] ?? 0) - (matchedByCurrency[code] ?? 0),
            ))
        .where((row) => row.balance.abs() > 0.000001)
        .toList()
      ..sort((a, b) => a.currency.compareTo(b.currency));
    return PartyAgingReport(
      partyType: partyType,
      asOf: asOf,
      rows: List.unmodifiable(reportRows),
      unallocated: List.unmodifiable(unallocated),
    );
  }

  Future<List<PartyStatementLine>> partyStatement({
    required int partyId,
    required String partyType,
    DateTime? from,
    DateTime? to,
    String? currency,
  }) async {
    if (partyType != 'customer' && partyType != 'supplier') {
      throw ArgumentError('نوع كشف الطرف غير صالح');
    }
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final parties = await db.query(
      'parties',
      columns: ['id', 'account_id'],
      where: 'id = ? AND lower(type) = ?',
      whereArgs: [partyId, partyType],
      limit: 1,
    );
    if (parties.isEmpty || parties.single['account_id'] == null) {
      throw StateError('الطرف غير موجود أو لا يملك حساباً تحليلياً');
    }
    final args = <Object?>[partyId, partyType, partyType];
    var extra = '';
    if (to != null) {
      extra += ' AND je.entry_date < ?';
      args.add(_reportDayAfter(to).toIso8601String());
    }
    final normalizedCurrency = currency?.trim().toUpperCase();
    if (normalizedCurrency != null && normalizedCurrency.isNotEmpty) {
      extra += ' AND UPPER(jl.currency) = ?';
      args.add(normalizedCurrency);
    }
    final entries = await db.rawQuery('''
      SELECT je.entry_date, je.number, je.description, UPPER(jl.currency) currency,
        jl.debit, jl.credit
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN parties p ON p.id = jl.party_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE p.id = ? AND lower(p.type) = ? AND a.kind = ?
        AND p.account_id = jl.account_id$extra
      ORDER BY je.entry_date, je.id, jl.id
    ''', args);
    final start = from == null ? null : _reportStartOfDay(from);
    final balances = <String, double>{};
    final statement = <PartyStatementLine>[];
    for (final row in entries) {
      final date = DateTime.parse(row['entry_date']! as String);
      final code = row['currency']! as String;
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();
      final signed = partyType == 'customer' ? debit - credit : credit - debit;
      final balance = (balances[code] ?? 0) + signed;
      balances[code] = balance;
      if (start != null && date.isBefore(start)) continue;
      statement.add(PartyStatementLine(
        date: date,
        number: row['number']! as String,
        description: row['description']! as String,
        currency: code,
        debit: debit,
        credit: credit,
        balance: balance,
      ));
    }
    return List.unmodifiable(statement);
  }
}

class _AgingAccumulator {
  final int partyId;
  final String partyName;
  final String currency;
  final List<_OpenAgingItem> _items = [];
  int _nextOpen = 0;
  double _credit = 0;

  _AgingAccumulator({
    required this.partyId,
    required this.partyName,
    required this.currency,
  });

  void apply(DateTime date, double amount, {DateTime? dueDate}) {
    if (amount > 0) {
      final applied = amount < _credit ? amount : _credit;
      _credit -= applied;
      final remainder = amount - applied;
      if (remainder > 0.000001) {
        _items.add(_OpenAgingItem(dueDate ?? date, remainder));
      }
      return;
    }
    var settlement = -amount;
    while (settlement > 0.000001 && _nextOpen < _items.length) {
      final item = _items[_nextOpen];
      final applied = settlement < item.amount ? settlement : item.amount;
      item.amount -= applied;
      settlement -= applied;
      if (item.amount <= 0.000001) _nextOpen++;
    }
    if (settlement > 0.000001) _credit += settlement;
  }

  PartyAgingRow finish(DateTime asOf) {
    var notDue = 0.0;
    var days0To30 = 0.0;
    var days31To60 = 0.0;
    var days61To90 = 0.0;
    var daysOver90 = 0.0;
    final cutoff = DateTime.utc(asOf.year, asOf.month, asOf.day);
    for (var index = _nextOpen; index < _items.length; index++) {
      final item = _items[index];
      final posted =
          DateTime.utc(item.date.year, item.date.month, item.date.day);
      final days = cutoff.difference(posted).inDays;
      if (days < 0) {
        notDue += item.amount;
      } else if (days <= 30) {
        days0To30 += item.amount;
      } else if (days <= 60) {
        days31To60 += item.amount;
      } else if (days <= 90) {
        days61To90 += item.amount;
      } else {
        daysOver90 += item.amount;
      }
    }
    return PartyAgingRow(
      partyId: partyId,
      partyName: partyName,
      currency: currency,
      notDue: notDue,
      days0To30: days0To30,
      days31To60: days31To60,
      days61To90: days61To90,
      daysOver90: daysOver90,
      unappliedCredit: _credit,
    );
  }
}

class _OpenAgingItem {
  final DateTime date;
  double amount;

  _OpenAgingItem(this.date, this.amount);
}
