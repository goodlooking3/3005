import 'dart:io';

const canonicalDatabaseFile = 'wasel.db';
const canonicalOwner = 'lib/data/local_database.dart';

void main() {
  final failures = <String>[];
  final roots = [Directory('lib'), Directory('test'), Directory('android')];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (!(path.endsWith('.dart') ||
          path.endsWith('.kt') ||
          path.endsWith('.java'))) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final match in RegExp(r'openDatabase\s*\(').allMatches(source)) {
        if (path != canonicalOwner) {
          failures.add(
              '$path:${source.substring(0, match.start).split('\n').length}: '
              'openDatabase must be owned by $canonicalOwner');
        }
      }
      if (source.contains('inMemoryDatabasePath')) {
        failures.add('$path: in-memory database is not allowed');
      }
      for (final match in RegExp(r'''["'][^"']+\.(db|sqlite|sqlite3)["']''')
          .allMatches(source)) {
        final value = match.group(0) ?? '';
        if (!value.contains(canonicalDatabaseFile) || path != canonicalOwner) {
          failures.add('$path: non-canonical database path $value');
        }
      }
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln('SQLite singleton policy failed:');
    stderr.writeAll(failures, '\n');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'SQLite singleton policy passed: all persistent access is owned by '
    '$canonicalOwner and uses $canonicalDatabaseFile.',
  );
}
