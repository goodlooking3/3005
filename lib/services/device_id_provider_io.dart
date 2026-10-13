import 'dart:io';

Future<({String machineGuid, String? systemUuid})>
    readWindowsMachineIdentifiers() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Device licensing is available on Windows only.');
  }
  final registry = await Process.run('reg.exe', [
    'query',
    r'HKLM\SOFTWARE\Microsoft\Cryptography',
    '/v',
    'MachineGuid',
  ]);
  if (registry.exitCode != 0) {
    throw const FormatException('تعذر قراءة معرّف تثبيت Windows.');
  }
  final match = RegExp(
    r'MachineGuid\s+REG_SZ\s+([^\r\n]+)',
    caseSensitive: false,
  ).firstMatch(registry.stdout.toString());
  final machineGuid = match?.group(1)?.trim();
  if (machineGuid == null || machineGuid.isEmpty) {
    throw const FormatException('تعذر قراءة معرّف تثبيت Windows.');
  }

  String? systemUuid;
  try {
    final result = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '(Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID',
    ]);
    if (result.exitCode == 0) {
      final candidate = result.stdout.toString().trim();
      final compact = candidate.replaceAll('-', '');
      if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact) &&
          !RegExp(r'^0+$').hasMatch(compact) &&
          !RegExp(r'^f+$').hasMatch(compact)) {
        systemUuid = candidate;
      }
    }
  } catch (_) {
    // MachineGuid remains a usable fallback when WMI is disabled.
  }
  return (machineGuid: machineGuid, systemUuid: systemUuid);
}
