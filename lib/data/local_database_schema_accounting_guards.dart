part of 'local_database_schema.dart';

Future<void> _createAccountingRoleGuards(Database db) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS phase2_voucher_insert_role_guard
    BEFORE INSERT ON vouchers
    WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
      NOT IN ('admin', 'owner', 'accountant')
    BEGIN
      SELECT RAISE(ABORT, 'role cannot post vouchers');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS phase2_journal_insert_role_guard
    BEFORE INSERT ON journal_entries
    WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
      NOT IN ('admin', 'owner', 'accountant')
    BEGIN
      SELECT RAISE(ABORT, 'role cannot post journal entries');
    END
  ''');
  for (final table in ['voucher_lines', 'journal_lines']) {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS phase2_${table}_insert_role_guard
      BEFORE INSERT ON $table
      WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
        NOT IN ('admin', 'owner', 'accountant')
      BEGIN
        SELECT RAISE(ABORT, 'role cannot post accounting lines');
      END
    ''');
  }
  for (final table in ['accounts', 'parties']) {
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final triggerName =
          'phase2_${table}_${operation.toLowerCase()}_role_guard';
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS $triggerName
        BEFORE $operation ON $table
        WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
          NOT IN ('admin', 'owner', 'accountant')
        BEGIN
          SELECT RAISE(ABORT, 'role cannot manage accounting master data');
        END
      ''');
    }
  }
  for (final operation in ['INSERT', 'UPDATE']) {
    final triggerName =
        'phase2_company_profile_${operation.toLowerCase()}_role_guard';
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS $triggerName
      BEFORE $operation ON company_profile
      WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
        NOT IN ('admin', 'owner')
      BEGIN
        SELECT RAISE(ABORT, 'role cannot manage company settings');
      END
    ''');
  }
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS phase2_period_insert_role_guard
    BEFORE INSERT ON accounting_periods
    WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
      NOT IN ('admin', 'owner')
    BEGIN
      SELECT RAISE(ABORT, 'role cannot create accounting periods');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS phase2_period_close_role_guard
    BEFORE UPDATE OF status ON accounting_periods
    WHEN OLD.status = 'open' AND NEW.status = 'closed'
      AND LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
        NOT IN ('admin', 'owner')
    BEGIN
      SELECT RAISE(ABORT, 'role cannot close accounting periods');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS phase2_user_role_self_escalation_guard
    BEFORE UPDATE OF role ON user_profile
    WHEN LOWER(COALESCE((SELECT role FROM user_profile WHERE id = 1), ''))
        NOT IN ('admin', 'owner')
      OR LOWER(NEW.role) NOT IN ('admin', 'owner', 'accountant', 'auditor', 'viewer')
    BEGIN
      SELECT RAISE(ABORT, 'role cannot change or elevate user profile');
    END
  ''');
}
