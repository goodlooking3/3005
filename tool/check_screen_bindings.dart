import 'dart:io';

const adapters = <String>{
  'lib/features/my_purchases/presentation/screens/vendor_store_screen.dart',
};

void main() {
  final failures = <String>[];
  final roots = [Directory('lib/features')];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final source = entity.readAsStringSync();
      if (!RegExp(r'class\s+\w+(Screen|Dashboard)').hasMatch(source)) continue;
      if (!source.contains('Widget build(')) {
        failures.add('$path: missing Widget build');
      }
      if (adapters.contains(path)) continue;
      final hasDataBinding = RegExp(
        r'LocalDatabase|Repository|Engine|Provider|Controller|Service|query\(|insert\(|update\(|delete\(',
      ).hasMatch(source);
      if (!hasDataBinding) failures.add('$path: no data binding detected');
      final hasInteraction = RegExp(
        r'onPressed:|onTap:|onChanged:|onSelectionChanged:',
      ).hasMatch(source);
      if (!hasInteraction) failures.add('$path: no user interaction detected');
      if (RegExp(r'\bTODO\b|coming soon|\bplaceholder\b', caseSensitive: false)
          .hasMatch(source)) {
        failures.add('$path: unresolved placeholder marker');
      }
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln('Screen binding policy failed:');
    stderr.writeAll(failures, '\n');
    exitCode = 1;
    return;
  }
  stdout.writeln('Screen binding policy passed.');
}
