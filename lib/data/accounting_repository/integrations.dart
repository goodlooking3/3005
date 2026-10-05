part of '../accounting_repository.dart';

extension AccountingRepositoryIntegrations on AccountingRepository {
  Future<int> pendingSyncCount() async =>
      Sqflite.firstIntValue(
        await (await _db).rawQuery(
          'SELECT COUNT(*) FROM sync_queue WHERE synced = 0',
        ),
      ) ??
      0;
  Future<List<Map<String, Object?>>> pendingSyncEnvelope() async =>
      (await _db).query('sync_queue', where: 'synced = 0', orderBy: 'id ASC');
  Future<void> markSynced(Iterable<int> ids) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          for (final id in ids) {
            await txn.update(
              'sync_queue',
              {'synced': 1},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        });
      });
  Future<void> recordConflict({
    required String entity,
    required int entityId,
    required String localHash,
    required String remoteHash,
  }) async =>
      AccountingRepositoryReports(this).log(
        'sync_conflict',
        '$entity:$entityId local=$localHash remote=$remoteHash',
      );

  Future<List<Remittance>> searchRemittances({
    String query = '',
    DateTime? from,
    DateTime? to,
    String? source,
  }) async {
    final args = <Object?>[];
    final where = <String>[];
    if (query.trim().isNotEmpty) {
      where.add(
        '(sender LIKE ? OR phone LIKE ? OR reference LIKE ? OR message LIKE ?)',
      );
      final q = '%${query.trim()}%';
      args.addAll([q, q, q, q]);
    }
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('created_at <= ?');
      args.add(to.toIso8601String());
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final rows = await (await _db).query(
      'remittances',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Remittance.fromMap).toList();
  }

  Future<void> saveConnector(ConnectorSettings settings) =>
      LocalDatabase.instance.write((db) async {
        await db.insert(
            'connector_configs',
            {
              'provider': settings.provider,
              'display_name': settings.displayName,
              'enabled': settings.enabled ? 1 : 0,
              'endpoint': settings.endpoint,
              'qr_payload': settings.qrPayload,
              'linked_account_id': settings.linkedAccountId,
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<int?> importBankSandboxTransaction({
    required int linkedAccountId,
    required BankSandboxTransaction transaction,
  }) =>
      LocalDatabase.instance.write((db) async {
        final existing = await db.query(
          'bank_transactions',
          columns: ['id'],
          where: 'provider = ? AND external_id = ?',
          whereArgs: ['bank_sandbox', transaction.externalId],
          limit: 1,
        );
        if (existing.isNotEmpty) return null;
        return db.insert('bank_transactions', {
          'provider': 'bank_sandbox',
          'external_id': transaction.externalId,
          'linked_account_id': linkedAccountId,
          'amount': transaction.amount,
          'currency': transaction.currency.trim().toUpperCase(),
          'direction': transaction.direction,
          'booked_at': transaction.bookedAt.toIso8601String(),
          'description': transaction.description.trim(),
          'imported_at': DateTime.now().toIso8601String(),
          'status': 'imported',
        });
      });

  Future<List<Map<String, Object?>>> bankSandboxTransactions() async =>
      (await _db).query(
        'bank_transactions',
        where: 'provider = ?',
        whereArgs: ['bank_sandbox'],
        orderBy: 'booked_at DESC, id DESC',
      );

  Future<int?> voucherIdByNumber(String number) async {
    final rows = await (await _db).query(
      'vouchers',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [number.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id'] as int;
  }

  Future<void> markBankSandboxPosted({
    required int id,
    required int voucherId,
  }) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          final rows = await txn.query(
            'bank_transactions',
            columns: ['status', 'posted_voucher_id'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isEmpty) throw StateError('حركة كشف البنك غير موجودة');
          if (rows.single['status'] == 'posted' &&
              rows.single['posted_voucher_id'] == voucherId) return;
          final changed = await txn.update(
            'bank_transactions',
            {'status': 'posted', 'posted_voucher_id': voucherId},
            where: 'id = ? AND status = ?',
            whereArgs: [id, 'imported'],
          );
          if (changed != 1) throw StateError('تعذر تحديث حالة حركة البنك');
        });
      });

  Future<int> postBankSandboxTransaction({
    required int id,
    required Voucher voucher,
  }) =>
      LocalDatabase.instance.write((db) async {
        return db.transaction((txn) async {
          final rows = await txn.query(
            'bank_transactions',
            columns: ['status', 'posted_voucher_id'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isEmpty) throw StateError('حركة كشف البنك غير موجودة');
          if (rows.single['status'] == 'posted') {
            final existingId = rows.single['posted_voucher_id'] as int?;
            if (existingId == null) {
              throw StateError('حركة البنك مرّحلة بلا مرجع قيد');
            }
            return existingId;
          }
          if (rows.single['status'] != 'imported') {
            throw StateError('حالة حركة البنك لا تسمح بالترحيل');
          }
          final voucherId = await insertVoucherInTransaction(txn, voucher);
          final changed = await txn.update(
            'bank_transactions',
            {'status': 'posted', 'posted_voucher_id': voucherId},
            where: 'id = ? AND status = ?',
            whereArgs: [id, 'imported'],
          );
          if (changed != 1) throw StateError('تعذر ربط قيد كشف البنك');
          return voucherId;
        });
      });

  Future<List<ConnectorSettings>> connectors() async {
    final rows = await (await _db).query(
      'connector_configs',
      orderBy: 'display_name ASC',
    );
    return rows
        .map(
          (r) => ConnectorSettings(
            provider: r['provider']! as String,
            displayName: r['display_name']! as String,
            enabled: (r['enabled'] as int) == 1,
            endpoint: r['endpoint'] as String?,
            qrPayload: r['qr_payload'] as String?,
            linkedAccountId: r['linked_account_id'] as int?,
          ),
        )
        .toList();
  }

  Future<int> addIncomingMessage(IncomingMessage message) =>
      LocalDatabase.instance.write(
        (db) => db.insert('incoming_messages', {
          'provider': message.provider,
          'sender': message.sender,
          'sender_phone': message.senderPhone,
          'body': message.body,
          'received_at': message.receivedAt.toIso8601String(),
          'archived': message.archived ? 1 : 0,
          'parsed_amount': message.parsedAmount,
          'parsed_currency': message.parsedCurrency,
          'reference': message.reference,
        }),
      );
  Future<List<IncomingMessage>> incomingMessages({
    bool archived = false,
  }) async {
    final rows = await (await _db).query(
      'incoming_messages',
      where: 'archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'received_at DESC',
    );
    return rows
        .map(
          (r) => IncomingMessage(
            id: r['id'] as int,
            provider: r['provider']! as String,
            sender: r['sender']! as String,
            senderPhone: r['sender_phone'] as String?,
            body: r['body']! as String,
            receivedAt: DateTime.parse(r['received_at']! as String),
            archived: (r['archived'] as int) == 1,
            parsedAmount: (r['parsed_amount'] as num?)?.toDouble(),
            parsedCurrency: r['parsed_currency'] as String?,
            reference: r['reference'] as String?,
          ),
        )
        .toList();
  }

  Future<void> archiveIncomingMessage(int id) =>
      LocalDatabase.instance.write((db) async {
        await db.update(
          'incoming_messages',
          {'archived': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditRepository.instance.recordOn(
          db,
          action: 'archive_message',
          entityType: 'incoming_message',
          entityId: '$id',
          details: 'message=$id',
        );
      });

  Future<List<JournalEntry>> journalEntries({String query = ''}) async {
    final trimmed = query.trim();
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query(
      'journal_entries',
      where: trimmed.isEmpty ? null : '(number LIKE ? OR description LIKE ?)',
      whereArgs: trimmed.isEmpty ? null : ['%$trimmed%', '%$trimmed%'],
      orderBy: 'entry_date DESC, id DESC',
    );
    return rows.map(JournalEntry.fromMap).toList(growable: false);
  }
}
