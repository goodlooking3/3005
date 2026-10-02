import '../../../../core/models.dart';
import '../../domain/models/wallet_model.dart';

class WalletNotificationParser {
  final List<WalletProviderConfig> providers;
  const WalletNotificationParser(this.providers);

  WalletTransactionDraft? parse(String text) {
    final provider = providers.cast<WalletProviderConfig?>().firstWhere(
          (item) => item!.keywords.any(
            (keyword) => text.toLowerCase().contains(keyword.toLowerCase()),
          ),
          orElse: () => null,
        );
    if (provider == null) return null;
    final parsed = MessageParser.parse(text);
    if (parsed.amount <= 0) return null;
    return WalletTransactionDraft(
      providerId: provider.id,
      amount: parsed.amount,
      currency: parsed.currency,
      reference: parsed.reference,
      rawText: text,
    );
  }
}

class WalletTransactionDraft {
  final String providerId;
  final double amount;
  final String currency;
  final String reference;
  final String rawText;

  const WalletTransactionDraft({
    required this.providerId,
    required this.amount,
    required this.currency,
    required this.reference,
    required this.rawText,
  });
}
