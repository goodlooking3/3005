import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveBackupBytes(List<int> bytes, String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
