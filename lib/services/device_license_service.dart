import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/device_license_format.dart';
import 'device_id_provider.dart';

class DeviceLicenseService {
  static const _storageKey = 'wasel_offline_device_license_v1';
  final Future<String> Function()? _deviceIdOverride;
  final String _publicKeyBase64Url;

  const DeviceLicenseService({
    Future<String> Function()? deviceIdProvider,
    String publicKeyBase64Url = DeviceLicenseFormat.signingPublicKeyBase64Url,
  })  : _deviceIdOverride = deviceIdProvider,
        _publicKeyBase64Url = publicKeyBase64Url;

  Future<String> deviceId() async {
    final override = _deviceIdOverride;
    if (override != null) {
      return DeviceLicenseFormat.normalizeDeviceId(await override());
    }
    final identifiers = await readWindowsMachineIdentifiers();
    return DeviceLicenseFormat.deriveDeviceId(
      machineGuid: identifiers.machineGuid,
      systemUuid: identifiers.systemUuid,
    );
  }

  Future<bool> hasValidStoredLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) return false;
      await DeviceLicenseFormat.verifyJson(
        json: stored,
        expectedDeviceId: await deviceId(),
        publicKeyBase64Url: _publicKeyBase64Url,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> activate(List<int> licenseBytes) async {
    final licenseJson = utf8.decode(licenseBytes);
    await DeviceLicenseFormat.verifyJson(
      json: licenseJson,
      expectedDeviceId: await deviceId(),
      publicKeyBase64Url: _publicKeyBase64Url,
    );
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_storageKey, licenseJson)) {
      throw StateError('تعذر حفظ ملف الترخيص محلياً.');
    }
  }
}
