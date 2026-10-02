import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> saveBackupBytes(List<int> bytes, String fileName) async {
  await FilePicker.saveFile(
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['wbackup'],
    bytes: Uint8List.fromList(bytes),
  );
  // Web saveFile starts a browser download and deliberately returns null.
  return fileName;
}
