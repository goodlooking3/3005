part of '../accounting_repository.dart';

extension AccountingRepositoryReports on AccountingRepository {
  Future<FinancialSummary> summary() async {
    final db = await _db;
    final totals = await db.rawQuery(
      '''SELECT
        COALESCE(SUM(COALESCE(jl.base_debit, jl.debit)), 0) debits,
        COALESCE(SUM(COALESCE(jl.base_credit, jl.credit)), 0) credits
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id''',
    );
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM vouchers'),
        ) ??
        0;
    final cash = await db.rawQuery('''
      SELECT COALESCE(SUM(a.opening_balance + COALESCE(j.debit, 0) - COALESCE(j.credit, 0)), 0) total
      FROM accounts a
      LEFT JOIN (
        SELECT jl.account_id,
          SUM(COALESCE(jl.base_debit, jl.debit)) debit,
          SUM(COALESCE(jl.base_credit, jl.credit)) credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        GROUP BY jl.account_id
      ) j ON j.account_id = a.id
      WHERE a.kind = 'cash' AND a.active = 1 AND a.is_group = 0
    ''');
    final bank = await db.rawQuery('''
      SELECT COALESCE(SUM(a.opening_balance + COALESCE(j.debit, 0) - COALESCE(j.credit, 0)), 0) total
      FROM accounts a
      LEFT JOIN (
        SELECT jl.account_id,
          SUM(COALESCE(jl.base_debit, jl.debit)) debit,
          SUM(COALESCE(jl.base_credit, jl.credit)) credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        GROUP BY jl.account_id
      ) j ON j.account_id = a.id
      WHERE a.kind = 'bank' AND a.active = 1 AND a.is_group = 0
    ''');
    return FinancialSummary(
      totalDebits: (totals.first['debits'] as num).toDouble(),
      totalCredits: (totals.first['credits'] as num).toDouble(),
      vouchersCount: count,
      cashBalance: (cash.first['total'] as num).toDouble(),
      bankBalance: (bank.first['total'] as num).toDouble(),
    );
  }

  Future<void> seedDemoAccountsForDevelopment({
    required bool explicitlyEnabled,
  }) async {
    if (!kDebugMode || !explicitlyEnabled) {
      throw StateError('بيانات العرض متاحة بتفعيل صريح في وضع التطوير فقط');
    }
    final existing = await (await _db).rawQuery(
      'SELECT COUNT(*) count FROM accounts WHERE is_group = 0',
    );
    if ((existing.first['count'] as int) > 0) {
      throw StateError('لا تُضاف بيانات العرض إلى دليل يحتوي حسابات فعلية');
    }
    for (final account in demoAccounts) {
      await AccountingRepositoryAccounts(this).upsertAccount(account);
    }
  }

  Future<void> log(String action, String details) =>
      AuditRepository.instance.record(
        action: action,
        entityType: 'application',
        details: details,
      );
  Future<List<AuditRecord>> audit() async {
    final rows = await (await _db).query(
      'audit_log',
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => AuditRecord(
            id: row['id'] as int?,
            createdAt: DateTime.parse(row['created_at']! as String),
            action: row['action']! as String,
            details: row['details']! as String,
            actorId: row['actor_id']! as String,
            sessionId: row['session_id'] as String?,
            entityType: row['entity_type']! as String,
            entityId: row['entity_id'] as String?,
            result: row['result']! as String,
          ),
        )
        .toList();
  }
}
