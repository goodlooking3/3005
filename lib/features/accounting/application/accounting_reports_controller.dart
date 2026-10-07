import 'package:flutter/foundation.dart';

import '../../../data/accounting_repository.dart';
import '../../../data/accounting_policy_repository.dart';
import '../../../data/currency_repository.dart';
import '../../../services/report_service.dart';
import '../domain/journal_entry.dart';

class AccountingReportsController extends ChangeNotifier {
  final AccountingRepository repository;
  final ReportService reportService;
  final CurrencyRepository currencyRepository;
  AccountingReportsController(
    this.repository, {
    ReportService? reportService,
    CurrencyRepository? currencyRepository,
  })  : reportService = reportService ?? ReportService(),
        currencyRepository = currencyRepository ?? CurrencyRepository();

  List<JournalEntry> journal = const [];
  List<AuditRecord> audit = const [];
  List<TrialBalanceRow> trialBalance = const [];
  List<CurrencyOption> currencies = const [];
  ProfitLossReport? profitLoss;
  ProfitLossReport? comparativeProfitLoss;
  BalanceSheetReport? balanceSheet;
  BalanceSheetReport? comparativeBalanceSheet;
  PartyAgingReport? receivablesAging;
  PartyAgingReport? payablesAging;
  List<CashFlowRow> cashFlow = const [];
  CashFlowReconciliation? cashFlowReconciliation;
  String? currency;
  DateTime? from;
  DateTime? to;
  DateTime? comparisonFrom;
  DateTime? comparisonTo;
  bool loading = false;
  String? error;

  Future<void> load({String query = ''}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      journal = await repository.journalEntries(query: query);
      audit = await repository.audit();
      trialBalance = await reportService.trialBalance(
        currency: currency,
        from: from,
        to: to,
      );
      profitLoss = await reportService.profitAndLoss(
        currency: currency,
        from: from,
        to: to,
      );
      currencies = await currencyRepository.activeCurrencies();
      final asOf = to ?? DateTime.now();
      balanceSheet = await reportService.balanceSheet(
        asOf: asOf,
        currency: currency,
      );
      receivablesAging = await reportService.receivablesAging(
        asOf: asOf,
        currency: currency,
      );
      payablesAging = await reportService.payablesAging(
        asOf: asOf,
        currency: currency,
      );
      cashFlow = await reportService.cashFlow(
        currency: currency,
        from: from,
        to: to,
      );
      cashFlowReconciliation = await reportService.cashFlowReconciliation(
        currency: currency,
        from: from,
        to: to,
      );
      final policy = await const AccountingPolicyRepository().load();
      final comparison = reportComparisonRange(
        from: from,
        to: to,
        basis: policy.comparativePeriodBasis,
      );
      comparisonFrom = comparison?.from;
      comparisonTo = comparison?.to;
      if (comparison == null) {
        comparativeProfitLoss = null;
        comparativeBalanceSheet = null;
      } else {
        comparativeProfitLoss = await reportService.profitAndLoss(
          currency: currency,
          from: comparison.from,
          to: comparison.to,
        );
        comparativeBalanceSheet = await reportService.balanceSheet(
          asOf: comparison.to,
          currency: currency,
        );
      }
    } catch (_) {
      error = 'تعذر تحميل التقارير وسجل التدقيق';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setCurrency(String? value) async {
    currency = value;
    await load();
  }

  Future<void> setDateRange(DateTime? start, DateTime? end) async {
    from = start;
    to = end;
    await load();
  }

  Future<List<PartyStatementLine>> loadPartyStatement({
    required int partyId,
    required String partyType,
  }) =>
      reportService.partyStatement(
        partyId: partyId,
        partyType: partyType,
        from: from,
        to: to,
        currency: currency,
      );
}

({DateTime from, DateTime to})? reportComparisonRange({
  required DateTime? from,
  required DateTime? to,
  required ComparativePeriodBasis basis,
}) {
  if (from == null || to == null || basis == ComparativePeriodBasis.none) {
    return null;
  }
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  if (end.isBefore(start)) return null;
  DateTime endOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999, 999);

  if (basis == ComparativePeriodBasis.previousYear) {
    DateTime previousYearDate(DateTime value) {
      final year = value.year - 1;
      final lastDay = DateTime(year, value.month + 1, 0).day;
      return DateTime(
        year,
        value.month,
        value.day.clamp(1, lastDay).toInt(),
      );
    }

    final comparisonStart = previousYearDate(start);
    final comparisonEnd = previousYearDate(end);
    return (from: comparisonStart, to: endOfDay(comparisonEnd));
  }

  final days = end.difference(start).inDays + 1;
  final comparisonEnd = start.subtract(const Duration(days: 1));
  final isFullCalendarMonth = start.day == 1 &&
      end.day == DateTime(end.year, end.month + 1, 0).day;
  final comparisonStart = isFullCalendarMonth
      ? DateTime(comparisonEnd.year, comparisonEnd.month)
      : comparisonEnd.subtract(Duration(days: days - 1));
  return (from: comparisonStart, to: endOfDay(comparisonEnd));
}
