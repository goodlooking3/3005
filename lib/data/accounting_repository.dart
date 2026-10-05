import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../core/accounting.dart';
import '../core/connector_models.dart';
import '../core/models.dart';
import 'local_database.dart';
import 'currency_policy.dart';
import 'audit_repository.dart';
import '../features/accounting/domain/journal_entry.dart';

part 'accounting_repository/posting.dart';
part 'accounting_repository/accounts.dart';
part 'accounting_repository/reports.dart';
part 'accounting_repository/integrations.dart';

class AuditRecord {
  final int? id;
  final DateTime createdAt;
  final String action;
  final String details;
  final String actorId;
  final String? sessionId;
  final String entityType;
  final String? entityId;
  final String result;

  const AuditRecord({
    this.id,
    required this.createdAt,
    required this.action,
    required this.details,
    this.actorId = 'legacy/unknown',
    this.sessionId,
    this.entityType = 'legacy/unknown',
    this.entityId,
    this.result = 'legacy/unknown',
  });
}

class AccountingRepository {
  Future<Database> get _db => LocalDatabase.instance.database;
}
