class WalletProviderConfig {
  final String id;
  final String name;
  final String? logoAsset;
  final List<String> keywords;
  final String? deepLink;
  final bool enabled;

  const WalletProviderConfig({
    required this.id,
    required this.name,
    this.logoAsset,
    this.keywords = const [],
    this.deepLink,
    this.enabled = true,
  });

  factory WalletProviderConfig.fromJson(Map<String, Object?> json) =>
      WalletProviderConfig(
        id: json['id']! as String,
        name: json['name']! as String,
        logoAsset: json['logoAsset'] as String?,
        keywords:
            (json['keywords'] as List<Object?>? ?? const []).cast<String>(),
        deepLink: json['deepLink'] as String?,
        enabled: json['enabled'] as bool? ?? true,
      );
}

class WalletAccount {
  final int? id;
  final int? accountId;
  final String? accountingCode;
  final String? accountingName;
  final String? externalType;
  final String? externalId;
  final String connectionStatus;
  final String balanceSource;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final String walletId;
  final String name;
  final String currency;
  final double balance;
  final bool active;

  const WalletAccount({
    this.id,
    this.accountId,
    this.accountingCode,
    this.accountingName,
    this.externalType,
    this.externalId,
    this.connectionStatus = 'not_connected',
    this.balanceSource = 'manual',
    this.lastSyncedAt,
    this.lastError,
    required this.walletId,
    required this.name,
    required this.currency,
    this.balance = 0,
    this.active = true,
  });

  factory WalletAccount.fromMap(Map<String, Object?> row) => WalletAccount(
        id: row['id'] as int?,
        accountId: row['account_id'] as int?,
        accountingCode: row['accounting_code'] as String?,
        accountingName: row['accounting_name'] as String?,
        externalType: row['external_type'] as String?,
        externalId: row['external_id'] as String?,
        connectionStatus: row['connection_status'] as String? ?? 'not_connected',
        balanceSource: row['balance_source'] as String? ?? 'manual',
        lastSyncedAt: row['last_synced_at'] == null
            ? null
            : DateTime.tryParse(row['last_synced_at']! as String),
        lastError: row['last_error'] as String?,
        walletId: row['wallet_id']! as String,
        name: row['name']! as String,
        currency: row['currency']! as String,
        balance: (row['balance']! as num).toDouble(),
        active: (row['active'] as int? ?? 1) == 1,
      );
}

class Wallet {
  final String id;
  final String name;
  final WalletProviderConfig provider;
  final List<WalletAccount> accounts;

  const Wallet({
    required this.id,
    required this.name,
    required this.provider,
    this.accounts = const [],
  });
}
