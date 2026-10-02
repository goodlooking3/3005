import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/models.dart';
import '../data/local_database.dart';

class BackupService {
  static Future<File> createBackup() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
        '${directory.path}/wasel-backup-${DateTime.now().toIso8601String().replaceAll(':', '-')}.json');
    final entries = await LocalDatabase.instance.all();
    await file.writeAsString(jsonEncode({
      'schema': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'remittances': entries.map((e) => e.toMap()).toList()
    }));
    return file;
  }

  static Future<int> restoreBackup(File file) async {
    final payload =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (payload['schema'] != 1 || payload['remittances'] is! List) {
      throw const FormatException('Invalid Wasel backup');
    }
    var restored = 0;
    for (final raw in payload['remittances'] as List) {
      final map = Map<String, Object?>.from(raw as Map);
      await LocalDatabase.instance.insert(__toRemittance(map));
      restored++;
    }
    return restored;
  }

  static Remittance __toRemittance(Map<String, Object?> map) => Remittance(
        createdAt: DateTime.parse(map['created_at']! as String),
        sender: map['sender']! as String,
        phone: map['phone']! as String,
        amount: (map['amount']! as num).toDouble(),
        currency: map['currency']! as String,
        reference: map['reference']! as String,
        message: map['message']! as String,
        source: map['source']! as String,
        type: (map['type'] as String?) == 'expense'
            ? EntryType.expense
            : EntryType.receipt,
      );
}
