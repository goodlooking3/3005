import 'package:flutter/foundation.dart';

import '../../../data/accounting_repository.dart';
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
  BalanceSheetReport? balanceSheet;
  PartyAgingReport? receivablesAging;
  PartyAgingReport? payablesAging;
  String? currency;
  DateTime? from;
  DateTime? to;
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
