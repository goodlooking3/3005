import 'dart:convert';

import '../../domain/models/wallet_model.dart';

class WalletProviderCatalog {
  final List<WalletProviderConfig> providers;
  const WalletProviderCatalog(this.providers);

  factory WalletProviderCatalog.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List<Object?>) {
      throw const FormatException('يجب أن يكون إعداد المحافظ قائمة JSON');
    }
    return WalletProviderCatalog(
      decoded
          .whereType<Map<String, Object?>>()
          .map(WalletProviderConfig.fromJson)
          .toList(growable: false),
    );
  }

  WalletProviderConfig? find(String id) => providers
      .cast<WalletProviderConfig?>()
      .firstWhere((item) => item!.id == id, orElse: () => null);
}
