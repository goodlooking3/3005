import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/device_license_format.dart';

void main() {
  const deviceId = '11223344556677889900AABBCCDDEEFF';
  const issuedAt = '2026-10-13T00:00:00.000Z';
  late SimpleKeyPair signingKey;
  late String publicKeyText;

  setUpAll(() async {
    signingKey = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (index) => index + 1),
    );
    publicKeyText = base64Url
        .encode((await signingKey.extractPublicKey()).bytes)
        .replaceAll('=', '');
  });

  Future<String> makeLicense({
    String targetDevice = deviceId,
    String licensee = 'اختبار داخلي',
  }) async {
    const licenseId = 'AABBCCDDEEFF00112233445566778899';
    final payload = DeviceLicenseFormat.canonicalPayload(
      deviceId: targetDevice,
      licensee: licensee,
      licenseId: licenseId,
      issuedAt: issuedAt,
    );
    final signature = await Ed25519().sign(
      utf8.encode(payload),
      keyPair: signingKey,
    );
    return jsonEncode({
      'schemaVersion': DeviceLicenseFormat.schemaVersion,
      'product': DeviceLicenseFormat.productId,
      'deviceId': targetDevice,
      'licensee': licensee,
      'licenseId': licenseId,
      'issuedAt': issuedAt,
      'signature': base64Url.encode(signature.bytes).replaceAll('=', ''),
    });
  }

  test('device ID hashes Windows identifiers without exposing raw values',
      () async {
    final first = await DeviceLicenseFormat.deriveDeviceId(
      machineGuid: 'ABCDEF01-2345-6789-ABCD-EF0123456789',
      systemUuid: '11111111-2222-3333-4444-555555555555',
    );
    final same = await DeviceLicenseFormat.deriveDeviceId(
      machineGuid: 'abcdef01-2345-6789-abcd-ef0123456789',
      systemUuid: '11111111-2222-3333-4444-555555555555',
    );
    final other = await DeviceLicenseFormat.deriveDeviceId(
      machineGuid: 'ABCDEF01-2345-6789-ABCD-EF0123456789',
      systemUuid: 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
    );
    expect(first, hasLength(32));
    expect(first, same);
    expect(first, isNot(other));
  });

  test('accepts a correctly signed license for the matching device', () async {
    await DeviceLicenseFormat.verifyJson(
      json: await makeLicense(),
      expectedDeviceId: deviceId,
      publicKeyBase64Url: publicKeyText,
    );
  });

  test('rejects a signed license copied to another device', () async {
    expect(
      DeviceLicenseFormat.verifyJson(
        json: await makeLicense(),
        expectedDeviceId: 'FFEEDDCCBBAA00998877665544332211',
        publicKeyBase64Url: publicKeyText,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects changed license data and malformed documents', () async {
    final document = jsonDecode(await makeLicense()) as Map<String, dynamic>;
    document['licensee'] = 'اسم مختلف';
    expect(
      DeviceLicenseFormat.verifyJson(
        json: jsonEncode(document),
        expectedDeviceId: deviceId,
        publicKeyBase64Url: publicKeyText,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      DeviceLicenseFormat.verifyJson(
        json: '{not-json',
        expectedDeviceId: deviceId,
        publicKeyBase64Url: publicKeyText,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
