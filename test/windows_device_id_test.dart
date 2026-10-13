import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/device_license_format.dart';
import 'package:wasel/services/device_id_provider.dart';

void main() {
  test('Windows device identifiers produce a normalized device ID', () async {
    if (!Platform.isWindows) return;
    final identifiers = await readWindowsMachineIdentifiers();
    expect(identifiers.machineGuid, isNotEmpty);
    final id = await DeviceLicenseFormat.deriveDeviceId(
      machineGuid: identifiers.machineGuid,
      systemUuid: identifiers.systemUuid,
    );
    expect(id, matches(RegExp(r'^[0-9A-F]{32}$')));
  });
}
