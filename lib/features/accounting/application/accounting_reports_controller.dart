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
      final results = await Future.wait<Object>([
        repository.journalEntries(query: query),
        repository.audit(),
        reportService.trialBalance(currency: currency, from: from, to: to),
        reportService.profitAndLoss(currency: currency, from: from, to: to),
        currencyRepository.activeCurrencies(),
      ]);
      journal = results[0] as List<JournalEntry>;
      audit = results[1] as List<AuditRecord>;
      trialBalance = results[2] as List<TrialBalanceRow>;
      profitLoss = results[3] as ProfitLossReport;
      currencies = results[4] as List<CurrencyOption>;
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
}
