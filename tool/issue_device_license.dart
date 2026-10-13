import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:wasel/core/device_license_format.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseOptions(arguments);
  if (options.containsKey('help')) {
    stdout.writeln('''
Usage:
  dart run tool/issue_device_license.dart \\
    --device-id <ID> --licensee <NAME> --private-key <SEED_FILE> \\
    --registry <REGISTRY_JSON> --output <LICENSE_JSON> [--license-id <32_HEX>]

The registry and private key must be stored securely outside the repository.
''');
    return;
  }

  final deviceId =
      DeviceLicenseFormat.normalizeDeviceId(_required(options, 'device-id'));
  final licensee = _required(options, 'licensee').trim();
  if (licensee.isEmpty ||
      licensee.length > 160 ||
      licensee.contains('\n') ||
      licensee.contains('\r')) {
    throw const FormatException(
        'Licensee must be 1-160 characters on one line.');
  }
  final privateKeyPath = _required(options, 'private-key');
  final registryPath = _required(options, 'registry');
  final outputPath = _required(options, 'output');
  final requestedLicenseId = options['license-id'];

  final seedText = (await File(privateKeyPath).readAsString()).trim();
  final seed = _decodeHex(seedText);
  if (seed.length != 32) {
    throw const FormatException('Ed25519 seed must be 32 bytes.');
  }
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyText = base64Url.encode(publicKey.bytes).replaceAll('=', '');
  if (publicKeyText != DeviceLicenseFormat.signingPublicKeyBase64Url) {
    throw const FormatException(
        'Private key does not match the application public key.');
  }

  final registryFile = File(registryPath);
  final registry = await _readRegistry(registryFile);
  final licenses = Map<String, dynamic>.from(registry['licenses'] as Map);
  final licenseId = requestedLicenseId == null
      ? _randomHex(16)
      : DeviceLicenseFormat.normalizeDeviceId(requestedLicenseId);
  final existing = licenses[licenseId];
  if (existing is Map && existing['deviceId'] != deviceId) {
    throw StateError(
      'This license ID is already bound to another device. '
      'Do not reassign offline licenses without understanding that old copies cannot be revoked.',
    );
  }

  final issuedAt = DateTime.now().toUtc().toIso8601String();
  final payload = DeviceLicenseFormat.canonicalPayload(
    deviceId: deviceId,
    licensee: licensee,
    licenseId: licenseId,
    issuedAt: issuedAt,
  );
  final signature =
      await algorithm.sign(utf8.encode(payload), keyPair: keyPair);
  final document = <String, Object>{
    'schemaVersion': DeviceLicenseFormat.schemaVersion,
    'product': DeviceLicenseFormat.productId,
    'deviceId': deviceId,
    'licensee': licensee,
    'licenseId': licenseId,
    'issuedAt': issuedAt,
    'signature': base64Url.encode(signature.bytes).replaceAll('=', ''),
  };
  final licenseJson = const JsonEncoder.withIndent('  ').convert(document);
  await DeviceLicenseFormat.verifyJson(
    json: licenseJson,
    expectedDeviceId: deviceId,
  );

  licenses[licenseId] = <String, String>{
    'deviceId': deviceId,
    'licensee': licensee,
    'issuedAt': issuedAt,
  };
  registry['licenses'] = licenses;
  await registryFile.parent.create(recursive: true);
  await _writeAtomically(
      registryFile, const JsonEncoder.withIndent('  ').convert(registry));
  final licenseFile = File(outputPath);
  await licenseFile.parent.create(recursive: true);
  await licenseFile.writeAsString('$licenseJson\n');
  stdout.writeln('Issued license ID: $licenseId');
  stdout.writeln('Bound device ID: ${_group(deviceId)}');
  stdout.writeln('Output: ${licenseFile.absolute.path}');
}

Map<String, String> _parseOptions(List<String> arguments) {
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--help' || argument == '-h') {
      values['help'] = '';
      continue;
    }
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      throw FormatException('Unexpected argument: $argument');
    }
    values[argument.substring(2)] = arguments[++index];
  }
  return values;
}

String _required(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.trim().isEmpty) {
    throw FormatException(
        'Missing required option --$name. Use --help for usage.');
  }
  return value;
}

Future<Map<String, dynamic>> _readRegistry(File file) async {
  if (!await file.exists()) {
    return <String, dynamic>{'schemaVersion': 1, 'licenses': {}};
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic> ||
      decoded['schemaVersion'] != 1 ||
      decoded['licenses'] is! Map) {
    throw const FormatException(
        'License registry file has an unsupported format.');
  }
  return decoded;
}

Future<void> _writeAtomically(File file, String content) async {
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString('$content\n', flush: true);
  if (await file.exists()) await file.delete();
  await temporary.rename(file.path);
}

List<int> _decodeHex(String value) {
  final normalized = value.replaceAll(RegExp(r'\s'), '');
  if (normalized.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
    throw const FormatException(
        'Private key file must contain hexadecimal bytes.');
  }
  return [
    for (var index = 0; index < normalized.length; index += 2)
      int.parse(normalized.substring(index, index + 2), radix: 16),
  ];
}

String _randomHex(int byteCount) => List<int>.generate(
      byteCount,
      (_) => Random.secure().nextInt(256),
    )
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

String _group(String id) =>
    RegExp(r'.{1,4}').allMatches(id).map((match) => match.group(0)).join('-');
