import 'dart:convert';
import 'package:http/http.dart' as http;

class SessionTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime issuedAt;
  const SessionTokens(
      {required this.accessToken,
      required this.refreshToken,
      required this.issuedAt});
}

class SessionTokenService {
  final http.Client client;
  const SessionTokenService(this.client);

  Future<SessionTokens> rotate(
      {required Uri endpoint, required String refreshToken}) async {
    if (endpoint.scheme != 'https') {
      throw ArgumentError('Token endpoint must use HTTPS');
    }
    final response = await client.post(endpoint,
        headers: {'content-type': 'application/json'},
        body: jsonEncode(
            {'grant_type': 'refresh_token', 'refresh_token': refreshToken}));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Token rotation failed with HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (payload['access_token'] is! String ||
        payload['refresh_token'] is! String) {
      throw const FormatException('Invalid token response');
    }
    return SessionTokens(
        accessToken: payload['access_token'] as String,
        refreshToken: payload['refresh_token'] as String,
        issuedAt: DateTime.now().toUtc());
  }
}
