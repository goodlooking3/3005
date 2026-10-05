import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/audit_repository.dart';

class AuthService {
  static const _minimumPasswordLength = 8;
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
    if (password.length < _minimumPasswordLength) {
      throw const FormatException('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim().toLowerCase());
    await prefs.setString(_phoneKey, phone.trim());
    await prefs.setString(_passwordKey, await _passwordHash(password));
    await prefs.setString(_displayNameKey,
        displayName.trim().isEmpty ? 'المستخدم' : displayName.trim());
    await prefs.setBool(_configuredKey, true);
    await AuditRepository.instance.record(
      action: 'auth.create_local_account',
      entityType: 'local_account',
      entityId: 'local-owner',
      details: 'تم إنشاء حساب محلي دون تسجيل كلمة المرور في سجل التدقيق',
    );
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
    final phoneMatches =
        phone.trim().isNotEmpty && prefs.getString(_phoneKey) == phone.trim();
    final accepted = (emailMatches || phoneMatches) &&
        await _matchesAndMigrate(prefs, password);
    if (accepted) await AuditRepository.instance.beginLocalOwnerSession();
    await AuditRepository.instance.record(
      action: 'auth.sign_in',
      entityType: 'local_account',
      entityId: 'local-owner',
      result: accepted ? 'success' : 'failure',
      details: 'password authentication',
    );
    return accepted;
  }

  Future<void> setRemembered(bool value, {bool keepSession = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, value);
    if (!value && !keepSession) {
      await AuditRepository.instance.record(
        action: 'auth.sign_out',
        entityType: 'local_account',
        entityId: 'local-owner',
        details: 'local session ended',
      );
      await AuditRepository.instance.endLocalOwnerSession();
    }
  }

  Future<bool> remembered() async =>
      (await SharedPreferences.getInstance()).getBool(_rememberKey) ?? false;

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < _minimumPasswordLength) {
      await AuditRepository.instance.record(
        action: 'auth.change_password',
        entityType: 'local_account',
        entityId: 'local-owner',
        result: 'failure',
        details: 'new password did not meet minimum length',
      );
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await _matchesAndMigrate(prefs, currentPassword)) {
      await AuditRepository.instance.record(
        action: 'auth.change_password',
        entityType: 'local_account',
        entityId: 'local-owner',
        result: 'failure',
        details: 'current password verification failed',
      );
      return false;
    }
    await prefs.setString(_passwordKey, await _passwordHash(newPassword));
    await AuditRepository.instance.record(
      action: 'auth.change_password',
      entityType: 'local_account',
      entityId: 'local-owner',
      details: 'password changed; secret omitted',
    );
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
    var accepted = false;
    try {
      accepted = await _localAuth.authenticate(
          localizedReason: 'افتح مساحة واصل الآمنة');
    } catch (_) {
      accepted = false;
    }
    if (accepted) await AuditRepository.instance.beginLocalOwnerSession();
    await AuditRepository.instance.record(
      action: 'auth.biometric_sign_in',
      entityType: 'local_account',
      entityId: 'local-owner',
      result: accepted ? 'success' : 'failure',
    );
    return accepted;
  }
}
