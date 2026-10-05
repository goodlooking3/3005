part of 'report_service.dart';

class FinancialPositionLine {
  final String code;
  final String account;
  final double balance;

  const FinancialPositionLine({
    required this.code,
    required this.account,
    required this.balance,
  });
}

class BalanceSheetReport {
  final DateTime asOf;
  final String currency;
  final List<FinancialPositionLine> assetsLines;
  final List<FinancialPositionLine> liabilitiesLines;
  final List<FinancialPositionLine> equityLines;
  final double assets;
  final double liabilities;
  final double equity;
  final double unclosedResult;

  const BalanceSheetReport({
    required this.asOf,
    required this.currency,
    required this.assetsLines,
    required this.liabilitiesLines,
    required this.equityLines,
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.unclosedResult,
  });

  double get liabilitiesAndEquity => liabilities + equity + unclosedResult;
  double get difference => assets - liabilitiesAndEquity;
  bool get isBalanced => difference.abs() <= 0.01;
}

extension ReportServiceBalanceSheet on ReportService {
  /// Builds a ledger-derived position as at end of day.
  /// Unclosed revenue/expense movements since the ledger opening are shown
  /// separately; a difference remains visible when opening balances or
  /// prior-period closing entries are incomplete.
  Future<BalanceSheetReport> balanceSheet({
    required DateTime asOf,
    String? currency,
  }) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final selectedCurrency = currency?.trim().toUpperCase();
    final baseCurrency = await currencyPolicy.requireBaseCurrency(db);
    final reportCurrency = selectedCurrency ?? baseCurrency;
    final cutoff = _reportEndOfDay(asOf);
    final balances = await AccountingRepository()
        .accountBalances(asOf: cutoff, includeInactive: true);
    final assets = <FinancialPositionLine>[];
    final liabilities = <FinancialPositionLine>[];
    final equity = <FinancialPositionLine>[];

    for (final item in balances.where((row) => !row.isGroup)) {
      if (selectedCurrency != null && item.currency != selectedCurrency) {
        continue;
      }
      final amount = selectedCurrency == null ? item.baseBalance : item.balance;
      if (amount == null || !amount.isFinite) {
        throw StateError(
          'تعذر إعداد قائمة المركز المالي: يوجد رصيد افتتاحي أو حركة أجنبية بلا تقييم أساس موثق',
        );
      }
      final line = FinancialPositionLine(
        code: item.accountCode,
        account: item.accountName,
        balance: amount,
      );
      switch (item.kind) {
        case AccountKind.asset:
        case AccountKind.cash:
        case AccountKind.bank:
        case AccountKind.customer:
          assets.add(line);
        case AccountKind.liability:
        case AccountKind.supplier:
          liabilities.add(line);
        case AccountKind.equity:
          equity.add(line);
        case AccountKind.revenue:
        case AccountKind.expense:
          break;
      }
    }

    assets.sort((a, b) => a.code.compareTo(b.code));
    liabilities.sort((a, b) => a.code.compareTo(b.code));
    equity.sort((a, b) => a.code.compareTo(b.code));
    final result = await profitAndLoss(
      currency: selectedCurrency,
      to: cutoff,
    );
    return BalanceSheetReport(
      asOf: asOf,
      currency: reportCurrency,
      assetsLines: List.unmodifiable(assets),
      liabilitiesLines: List.unmodifiable(liabilities),
      equityLines: List.unmodifiable(equity),
      assets: assets.fold(0, (sum, line) => sum + line.balance),
      liabilities: liabilities.fold(0, (sum, line) => sum + line.balance),
      equity: equity.fold(0, (sum, line) => sum + line.balance),
      unclosedResult: result.net,
    );
  }
}

DateTime _reportEndOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999, 999);

DateTime _reportStartOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _reportDayAfter(DateTime value) =>
    DateTime(value.year, value.month, value.day + 1);
