import 'package:flutter/foundation.dart';

import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';
import 'chart_account_catalog.dart';
import '../presentation/account_tree.dart';

class ChartOfAccountsController extends ChangeNotifier {
  final AccountingRepository repository;
  ChartOfAccountsController(this.repository);

  List<Account> _allAccounts = const [];
  String query = '';
  AccountKind? kind;
  bool includeInactive = false;
  final expanded = <int>{};
  bool loading = false;
  Object? error;

  List<Account> get accounts => filterAccounts(
        _allAccounts,
        query: query,
        kind: kind,
        includeInactive: includeInactive,
      );

  List<Account> get allAccounts => List.unmodifiable(_allAccounts);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await repository.seedDefaultAccounts();
      await ChartAccountCatalog(repository).ensureDefaults();
      _allAccounts = await repository.accounts(includeInactive: true);
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setKind(AccountKind? value) {
    kind = value;
    notifyListeners();
  }

  void setIncludeInactive(bool value) {
    includeInactive = value;
    notifyListeners();
  }

  void toggleExpanded(int id) {
    if (!expanded.add(id)) expanded.remove(id);
    notifyListeners();
  }

  Future<void> setActive(Account account, bool active) async {
    await repository.setAccountActive(account.id!, active);
    await load();
  }
}
