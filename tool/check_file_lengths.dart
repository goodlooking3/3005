import 'dart:io';

const warningLines = 400;
const maxLines = 500;
const frozenLegacy = <String>{
  'lib/main.dart',
  // HomeShell is isolated from application bootstrap; its callbacks still
  // share one StatefulWidget state and need a dedicated behavior-preserving
  // extraction pass before this exception can be removed.
  'lib/app_shell_part.dart',
};

void main() {
  final warnings = <String>[];
  final violations = <String>[];
  for (final root in ['lib', 'test']) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceAll('\\', '/');
      final lines = entity.readAsLinesSync().length;
      if (lines >= warningLines) {
        warnings.add('$relative: $lines lines (warning threshold $warningLines)');
      }
      if (lines > maxLines && !frozenLegacy.contains(relative)) {
        violations.add('$relative: $lines lines (limit $maxLines)');
      }
    }
  }
  if (warnings.isNotEmpty) {
    stdout.writeln('File length policy warnings:');
    stdout.writeAll(warnings, '\n');
  }
  if (violations.isNotEmpty) {
    stderr.writeln('File length policy failed:');
    stderr.writeAll(violations, '\n');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'File length policy passed. Frozen legacy exceptions: '
    '${frozenLegacy.join(', ')}. Warning threshold: $warningLines; hard limit: $maxLines.',
  );
}
