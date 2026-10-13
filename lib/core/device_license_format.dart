import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class DeviceLicenseFormat {
  static const schemaVersion = 1;
  static const productId = 'wasel-windows';
  static const signingPublicKeyBase64Url =
      'FyFxpJc00_dTy9LS1NT4GOgY7IqIXy5kscUmpT6WaIc';

  static String normalizeDeviceId(String value) {
    final normalized = value.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(normalized)) {
      throw const FormatException('معرّف الجهاز غير صالح.');
    }
    return normalized;
  }

  static Future<String> deriveDeviceId({
    required String machineGuid,
    String? systemUuid,
  }) async {
    final guid = machineGuid.trim().toLowerCase();
    if (guid.isEmpty) throw const FormatException('تعذر قراءة معرّف Windows.');
    final uuid = _usableUuid(systemUuid);
    final material = 'wasel-device-v1\n$guid\n${uuid ?? 'no-smbios-uuid'}';
    final digest = await Sha256().hash(utf8.encode(material));
    return digest.bytes
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  static String? _usableUuid(String? value) {
    final uuid = value?.trim().toLowerCase();
    if (uuid == null || uuid.isEmpty) return null;
    final compact = uuid.replaceAll('-', '');
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(compact) ||
        RegExp(r'^0+$').hasMatch(compact) ||
        RegExp(r'^f+$').hasMatch(compact)) {
      return null;
    }
    return compact;
  }

  static String canonicalPayload({
    required String deviceId,
    required String licensee,
    required String licenseId,
    required String issuedAt,
  }) =>
      [
        'wasel-offline-license-v1',
        productId,
        normalizeDeviceId(deviceId),
        licensee,
        licenseId,
        issuedAt,
      ].join('\n');

  static Future<void> verifyJson({
    required String json,
    required String expectedDeviceId,
    String publicKeyBase64Url = signingPublicKeyBase64Url,
  }) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ملف الترخيص ليس بصيغة JSON صحيحة.');
    }
    if (decoded['schemaVersion'] != schemaVersion ||
        decoded['product'] != productId) {
      throw const FormatException('ملف الترخيص لا يخص إصدار واصل هذا.');
    }

    final deviceId = normalizeDeviceId(_requiredString(decoded, 'deviceId'));
    if (deviceId != normalizeDeviceId(expectedDeviceId)) {
      throw const FormatException('هذا الترخيص مرتبط بجهاز آخر.');
    }
    final licensee = _requiredString(decoded, 'licensee');
    final licenseId = _requiredString(decoded, 'licenseId');
    final issuedAt = _requiredString(decoded, 'issuedAt');
    final signatureText = _requiredString(decoded, 'signature');
    if (licensee.trim().isEmpty ||
        licensee.length > 160 ||
        licensee.contains('\n') ||
        licensee.contains('\r') ||
        !RegExp(r'^[0-9A-F]{32}$').hasMatch(licenseId) ||
        DateTime.tryParse(issuedAt) == null) {
      throw const FormatException('بيانات الترخيص غير مكتملة أو غير صالحة.');
    }

    final signatureBytes = base64Url.decode(base64Url.normalize(signatureText));
    final publicKeyBytes = base64Url.decode(
      base64Url.normalize(publicKeyBase64Url),
    );
    if (signatureBytes.length != 64 || publicKeyBytes.length != 32) {
      throw const FormatException('توقيع الترخيص غير صالح.');
    }
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final signature = Signature(signatureBytes, publicKey: publicKey);
    final valid = await Ed25519().verify(
      utf8.encode(
        canonicalPayload(
          deviceId: deviceId,
          licensee: licensee,
          licenseId: licenseId,
          issuedAt: issuedAt,
        ),
      ),
      signature: signature,
    );
    if (!valid) {
      throw const FormatException('توقيع الترخيص غير صحيح أو تم تعديله.');
    }
  }

  static String _requiredString(Map<String, dynamic> values, String key) {
    final value = values[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('حقل الترخيص مفقود: $key');
    }
    return value;
  }
}
