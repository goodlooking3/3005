import 'package:flutter/foundation.dart';

import '../../domain/models/wallet_model.dart';
import '../../domain/models/wallet_transaction.dart';
import '../../domain/repositories/i_wallet_repository.dart';
import '../../../accounting/application/chart_account_catalog.dart';
import '../../../../data/accounting_repository.dart';

class WalletProvider extends ChangeNotifier {
  final IWalletRepository repository;
  final ChartAccountCatalog chartCatalog;
  WalletProvider(this.repository, {ChartAccountCatalog? chartCatalog})
      : chartCatalog = chartCatalog ?? ChartAccountCatalog(AccountingRepository());

  List<Wallet> wallets = const [];
  List<WalletTransaction> transactions = const [];
  WalletTransactionFilter filter = const WalletTransactionFilter();
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      wallets = await repository.wallets();
      transactions = await repository.transactions(filter: filter);
    } catch (_) {
      error = 'تعذر تحميل بيانات المحافظ';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> applyFilter(WalletTransactionFilter value) async {
    filter = value;
    transactions = await repository.transactions(filter: value);
    notifyListeners();
  }

  Future<void> addTransaction(WalletTransaction value) async {
    await repository.saveTransaction(value);
    await load();
  }

  Future<void> addWallet(Wallet wallet, {WalletAccount? account}) async {
    if (account != null) {
      final linked = await chartCatalog.ensureWalletAccount(
        walletName: account.name,
        currency: account.currency,
      );
      await repository.saveWalletWithAccount(wallet, WalletAccount(
        id: account.id,
        accountId: linked.id,
        accountingCode: linked.code,
        accountingName: linked.name,
        walletId: account.walletId,
        name: account.name,
        currency: account.currency,
        balance: account.balance,
        active: account.active,
      ));
    } else {
      await repository.saveWallet(wallet);
    }
    await load();
  }

  Future<void> importTransactions(List<WalletTransaction> values) async {
    await repository.importTransactions(values);
    await load();
  }
}
