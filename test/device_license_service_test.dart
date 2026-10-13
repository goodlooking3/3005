import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasel/core/device_license_format.dart';
import 'package:wasel/services/device_license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceId = '11223344556677889900AABBCCDDEEFF';
  const otherDeviceId = 'FFEEDDCCBBAA00998877665544332211';
  const issuedAt = '2026-10-13T00:00:00.000Z';
  late SimpleKeyPair keyPair;
  late String publicKeyText;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    keyPair = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (index) => index + 3),
    );
    publicKeyText = base64Url
        .encode((await keyPair.extractPublicKey()).bytes)
        .replaceAll('=', '');
  });

  Future<List<int>> makeLicense(String targetDevice) async {
    const licenseId = 'AABBCCDDEEFF00112233445566778899';
    const licensee = 'عميل تجريبي';
    final payload = DeviceLicenseFormat.canonicalPayload(
      deviceId: targetDevice,
      licensee: licensee,
      licenseId: licenseId,
      issuedAt: issuedAt,
    );
    final signature = await Ed25519().sign(
      utf8.encode(payload),
      keyPair: keyPair,
    );
    return utf8.encode(jsonEncode({
      'schemaVersion': DeviceLicenseFormat.schemaVersion,
      'product': DeviceLicenseFormat.productId,
      'deviceId': targetDevice,
      'licensee': licensee,
      'licenseId': licenseId,
      'issuedAt': issuedAt,
      'signature': base64Url.encode(signature.bytes).replaceAll('=', ''),
    }));
  }

  test('stores and accepts a signed license only for its device ID', () async {
    final service = DeviceLicenseService(
      deviceIdProvider: () async => deviceId,
      publicKeyBase64Url: publicKeyText,
    );
    await service.activate(await makeLicense(deviceId));
    expect(await service.hasValidStoredLicense(), isTrue);

    final copiedToAnotherDevice = DeviceLicenseService(
      deviceIdProvider: () async => otherDeviceId,
      publicKeyBase64Url: publicKeyText,
    );
    expect(await copiedToAnotherDevice.hasValidStoredLicense(), isFalse);
  });

  test('does not store a license issued for a different device', () async {
    final service = DeviceLicenseService(
      deviceIdProvider: () async => deviceId,
      publicKeyBase64Url: publicKeyText,
    );
    expect(
      service.activate(await makeLicense(otherDeviceId)),
      throwsA(isA<FormatException>()),
    );
    expect(await service.hasValidStoredLicense(), isFalse);
  });
}
