import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/models.dart';
import '../data/local_database.dart';
import 'backup_store_web.dart' if (dart.library.io) 'backup_store_default.dart'
    as backup_store;

class SecureBackupService {
  static const _keyName = 'wasel_backup_key_v1';
  static const _storage = FlutterSecureStorage();
  static final _cipher = AesGcm.with256bits();

  static Future<SecretKey> _key() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return SecretKey(base64Url.decode(existing));
    final generated = await _cipher.newSecretKey();
    final bytes = await generated.extractBytes();
    await _storage.write(key: _keyName, value: base64UrlEncode(bytes));
    return generated;
  }

  static Future<String?> createEncryptedBackup() async {
    final entries = await LocalDatabase.instance.all();
    final payload = utf8.encode(jsonEncode({
      'schema': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'remittances': entries.map((entry) => entry.toMap()).toList(),
    }));
    final box = await _cipher.encrypt(payload, secretKey: await _key());
    final envelope = jsonEncode({
      'version': 1,
      'nonce': base64UrlEncode(box.nonce),
      'cipherText': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
    final name =
        'wasel-backup-${DateTime.now().millisecondsSinceEpoch}.wbackup';
    return backup_store.saveBackupBytes(utf8.encode(envelope), name);
  }

  static Future<int> restoreEncryptedBackup(List<int> bytes) async {
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (envelope['version'] != 1) {
      throw const FormatException('Unsupported encrypted backup');
    }
    final box = SecretBox(
      base64Url.decode(envelope['cipherText'] as String),
      nonce: base64Url.decode(envelope['nonce'] as String),
      mac: Mac(base64Url.decode(envelope['mac'] as String)),
    );
    final data = jsonDecode(
      utf8.decode(await _cipher.decrypt(box, secretKey: await _key())),
    ) as Map<String, dynamic>;
    if (data['schema'] != 2 || data['remittances'] is! List) {
      throw const FormatException('Invalid encrypted backup payload');
    }

    return LocalDatabase.instance.write((db) async {
      var restored = 0;
      await db.transaction((txn) async {
        for (final raw in data['remittances'] as List) {
          final item = Remittance.fromMap(
            Map<String, Object?>.from(raw as Map),
          );
          final duplicate = await txn.query(
            'remittances',
            columns: ['id'],
            where: 'created_at = ? AND reference = ? AND source = ?',
            whereArgs: [
              item.createdAt.toIso8601String(),
              item.reference,
              item.source,
            ],
            limit: 1,
          );
          if (duplicate.isNotEmpty) continue;
          await txn.insert('remittances', item.toMap()..remove('id'));
          restored++;
        }
      });
      return restored;
    });
  }
}
