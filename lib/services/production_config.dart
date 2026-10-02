class ProductionConfig {
  static const syncEndpoint =
      String.fromEnvironment('WASEL_SYNC_ENDPOINT', defaultValue: '');
  static const clientId =
      String.fromEnvironment('WASEL_CLIENT_ID', defaultValue: '');
  static const buildFlavor =
      String.fromEnvironment('WASEL_FLAVOR', defaultValue: 'preview');

  static bool get hasSyncEndpoint => syncEndpoint.startsWith('https://');
  static Uri get syncUri => Uri.parse(syncEndpoint);
  static void validate() {
    if (syncEndpoint.isNotEmpty && !hasSyncEndpoint) {
      throw const FormatException('WASEL_SYNC_ENDPOINT must use HTTPS');
    }
    if (buildFlavor == 'production' && clientId.isEmpty) {
      throw const FormatException('WASEL_CLIENT_ID is required in production');
    }
  }
}

class TokenRotationPolicy {
  final Duration accessTokenLifetime;
  final Duration refreshTokenLifetime;
  const TokenRotationPolicy(
      {this.accessTokenLifetime = const Duration(minutes: 15),
      this.refreshTokenLifetime = const Duration(days: 30)});
  bool requiresRefresh(DateTime issuedAt, DateTime now) =>
      now.difference(issuedAt) >= accessTokenLifetime;
  bool refreshExpired(DateTime issuedAt, DateTime now) =>
      now.difference(issuedAt) >= refreshTokenLifetime;
}
