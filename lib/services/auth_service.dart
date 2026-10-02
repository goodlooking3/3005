import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _configuredKey = 'wasel_auth_configured';
  static const _emailKey = 'wasel_auth_email';
  static const _phoneKey = 'wasel_auth_phone';
  static const _passwordKey = 'wasel_auth_password';
  static const _displayNameKey = 'wasel_auth_display_name';
  static const _rememberKey = 'wasel_auth_remember';
  static const _hashPrefix = 'sha256:';
  final LocalAuthentication _localAuth = LocalAuthentication();
  static final _hash = Sha256();

  Future<bool> hasAccount() async =>
      (await SharedPreferences.getInstance()).getBool(_configuredKey) ?? false;

  Future<void> createAccount({
    String email = '',
    String phone = '',
    required String password,
    String displayName = 'المستخدم',
  }) async {
    if (email.trim().isEmpty && phone.trim().isEmpty) {
      throw const FormatException('البريد الإلكتروني أو رقم الهاتف مطلوب');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim().toLowerCase());
    await prefs.setString(_phoneKey, phone.trim());
    await prefs.setString(_passwordKey, await _passwordHash(password));
    await prefs.setString(_displayNameKey,
        displayName.trim().isEmpty ? 'المستخدم' : displayName.trim());
    await prefs.setBool(_configuredKey, true);
  }

  Future<String> displayName() async =>
      (await SharedPreferences.getInstance()).getString(_displayNameKey) ??
      'المستخدم';

  Future<bool> signIn({
    required String email,
    required String password,
    String phone = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = email.trim();
    final emailMatches = identifier.isNotEmpty &&
        prefs.getString(_emailKey) == identifier.toLowerCase();
    final phoneMatches = phone.trim().isNotEmpty &&
        prefs.getString(_phoneKey) == phone.trim();
    if (!(emailMatches || phoneMatches)) return false;
    return _matchesAndMigrate(prefs, password);
  }

  Future<void> setRemembered(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, value);
  }

  Future<bool> remembered() async =>
      (await SharedPreferences.getInstance()).getBool(_rememberKey) ?? false;

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) return false;
    final prefs = await SharedPreferences.getInstance();
    if (!await _matchesAndMigrate(prefs, currentPassword)) return false;
    await prefs.setString(_passwordKey, await _passwordHash(newPassword));
    return true;
  }

  Future<bool> _matchesAndMigrate(
    SharedPreferences prefs,
    String password,
  ) async {
    final stored = prefs.getString(_passwordKey);
    if (stored == null) return false;
    final hashed = await _passwordHash(password);
    if (stored == hashed) return true;
    if (stored == password) {
      await prefs.setString(_passwordKey, hashed);
      return true;
    }
    return false;
  }

  Future<String> _passwordHash(String password) async {
    final digest = await _hash.hash(utf8.encode(password));
    return '$_hashPrefix${base64UrlEncode(digest.bytes)}';
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
          localizedReason: 'افتح مساحة واصل الآمنة');
    } catch (_) {
      return false;
    }
  }
}
