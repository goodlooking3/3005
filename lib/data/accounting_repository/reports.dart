part of '../accounting_repository.dart';

extension AccountingRepositoryReports on AccountingRepository {
  Future<FinancialSummary> summary() async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final balances = await accountBalances(includeInactive: true);
    var debits = 0.0;
    var credits = 0.0;
    var cashBalance = 0.0;
    var bankBalance = 0.0;
    for (final balance in balances) {
      if ((balance.debitTotal > accountingTolerance ||
              balance.creditTotal > accountingTolerance) &&
          (balance.baseDebitTotal == null || balance.baseCreditTotal == null)) {
        throw StateError(
          'تعذر جمع الرصيد الأساسي للحساب ${balance.accountCode} بعملة ${balance.currency}',
        );
      }
      debits += balance.baseDebitTotal ?? 0;
      credits += balance.baseCreditTotal ?? 0;
      if (!balance.isGroup &&
          (balance.kind == AccountKind.cash ||
              balance.kind == AccountKind.bank)) {
        final baseBalance = balance.baseBalance;
        if (baseBalance == null) {
          throw StateError(
            'رصيد افتتاحي غير مقوم للحساب ${balance.accountCode}؛ لا يمكن جمع أرصدة الصندوق/البنك',
          );
        }
        if (balance.kind == AccountKind.cash) cashBalance += baseBalance;
        if (balance.kind == AccountKind.bank) bankBalance += baseBalance;
      }
    }
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM vouchers'),
        ) ??
        0;
    return FinancialSummary(
      totalDebits: debits,
      totalCredits: credits,
      vouchersCount: count,
      cashBalance: cashBalance,
      bankBalance: bankBalance,
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
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewAudit);
    final rows = await db.query(
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
