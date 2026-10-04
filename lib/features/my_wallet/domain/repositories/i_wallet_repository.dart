import '../models/wallet_model.dart';
import '../models/wallet_transaction.dart';

abstract interface class IWalletRepository {
  Future<List<Wallet>> wallets();
  Future<List<WalletTransaction>> transactions({
    WalletTransactionFilter filter = const WalletTransactionFilter(),
  });
  Future<int> saveWallet(Wallet wallet);
  Future<int> saveAccount(WalletAccount account);
  Future<void> saveAccounts(List<WalletAccount> accounts);
  Future<void> saveWalletWithAccount(Wallet wallet, WalletAccount account);
  Future<int> saveTransaction(WalletTransaction transaction);
  Future<void> importTransactions(List<WalletTransaction> transactions);
}
