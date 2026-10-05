import 'package:sqflite/sqflite.dart';

enum AccountingPermission {
  viewLedger,
  viewAudit,
  manageAccounts,
  manageParties,
  postVouchers,
  reverseVouchers,
  managePeriods,
  closePeriods,
  manageCompanySettings,
}

class AuthorizationDeniedException implements Exception {
  final AccountingPermission permission;
  final String role;

  const AuthorizationDeniedException(this.permission, this.role);

  @override
  String toString() =>
      'Authorization denied: ${permission.name} for role ${role.isEmpty ? "unknown" : role}';
}

/// Repository/service policy. Unknown and missing roles are denied by default.
class AccountingAuthorization {
  AccountingAuthorization._();

  static final instance = AccountingAuthorization._();

  static const _all = <AccountingPermission>{
    AccountingPermission.viewLedger,
    AccountingPermission.viewAudit,
    AccountingPermission.manageAccounts,
    AccountingPermission.manageParties,
    AccountingPermission.postVouchers,
    AccountingPermission.reverseVouchers,
    AccountingPermission.managePeriods,
    AccountingPermission.closePeriods,
    AccountingPermission.manageCompanySettings,
  };

  static const _rolePermissions = <String, Set<AccountingPermission>>{
    'admin': _all,
    'owner': _all,
    'accountant': {
      AccountingPermission.viewLedger,
      AccountingPermission.manageAccounts,
      AccountingPermission.manageParties,
      AccountingPermission.postVouchers,
      AccountingPermission.reverseVouchers,
    },
    'auditor': {
      AccountingPermission.viewLedger,
      AccountingPermission.viewAudit,
    },
    'viewer': {AccountingPermission.viewLedger},
  };

  Future<String> role(DatabaseExecutor db) async {
    final rows = await db.query(
      'user_profile',
      columns: ['role'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    return (rows.isEmpty ? '' : rows.single['role'] as String? ?? '')
        .trim()
        .toLowerCase();
  }

  Future<bool> can(
    DatabaseExecutor db,
    AccountingPermission permission,
  ) async {
    final current = await role(db);
    return _rolePermissions[current]?.contains(permission) ?? false;
  }

  Future<void> require(
    DatabaseExecutor db,
    AccountingPermission permission,
  ) async {
    final current = await role(db);
    if (!(_rolePermissions[current]?.contains(permission) ?? false)) {
      throw AuthorizationDeniedException(permission, current);
    }
  }

  /// Use for reads, which are not wrapped in LocalDatabase.write's failure audit.
  Future<void> requireRead(
    DatabaseExecutor db,
    AccountingPermission permission,
  ) async {
    try {
      await require(db, permission);
    } on AuthorizationDeniedException catch (error) {
      try {
        final contexts = await db.query(
          'audit_context',
          columns: ['actor_id', 'session_id'],
          where: 'id = ?',
          whereArgs: [1],
          limit: 1,
        );
        final context = contexts.isEmpty ? null : contexts.single;
        await db.insert('audit_log', {
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'actor_id': context?['actor_id'] ?? 'local-owner',
          'session_id': context?['session_id'],
          'entity_type': 'permission',
          'entity_id': permission.name,
          'action': 'authorization.denied',
          'result': 'failure',
          'details': 'role=${error.role}; required=${permission.name}',
        });
      } catch (_) {
        // Keep the original denial even when the local audit sink is unavailable.
      }
      rethrow;
    }
  }
}
