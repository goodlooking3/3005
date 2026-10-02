import 'dart:convert';

import '../../domain/models/wallet_model.dart';

class DeepLinkAutomation {
  final Future<bool> Function(Uri uri)? launch;
  const DeepLinkAutomation({this.launch});

  Future<bool> openTransfer({
    required WalletProviderConfig provider,
    required String recipient,
    required double amount,
    required String currency,
    String note = '',
  }) async {
    final template = provider.deepLink;
    if (template == null || template.trim().isEmpty || launch == null) {
      return false;
    }
    final uri = Uri.parse(template).replace(
      queryParameters: {
        'recipient': recipient,
        'amount': amount.toString(),
        'currency': currency,
        'note': note,
      },
    );
    return launch!(uri);
  }

  String buildIntentPayload({
    required WalletProviderConfig provider,
    required String recipient,
    required double amount,
    required String currency,
    String note = '',
  }) =>
      jsonEncode({
        'provider': provider.id,
        'recipient': recipient,
        'amount': amount,
        'currency': currency,
        'note': note,
      });
}
