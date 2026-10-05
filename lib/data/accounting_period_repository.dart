import '../core/accounting.dart';
import 'accounting_authorization.dart';
import 'local_database.dart';

class AccountingPeriodRepository {
  const AccountingPeriodRepository();

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<int> createPeriod({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      LocalDatabase.instance.write((db) async {
        return db.transaction((txn) async {
          await AccountingAuthorization.instance
              .require(txn, AccountingPermission.managePeriods);
          final periodName = name.trim();
          final start = _dateOnly(startDate);
          final end = _dateOnly(endDate);
          if (periodName.isEmpty ||
              periodName.length > 80 ||
              start.compareTo(end) > 0) {
            throw ArgumentError('اسم الفترة ونطاق التاريخ غير صالحين');
          }
          final overlap = await txn.query(
            'accounting_periods',
            columns: ['id'],
            where: 'start_date <= ? AND end_date >= ?',
            whereArgs: [end, start],
            limit: 1,
          );
          if (overlap.isNotEmpty) {
            throw StateError('الفترات المالية لا يجوز أن تتداخل');
          }
          return txn.insert('accounting_periods', {
            'name': periodName,
            'start_date': start,
            'end_date': end,
            'status': 'open',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        });
      });

  Future<void> closePeriod(int periodId) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          await AccountingAuthorization.instance
              .require(txn, AccountingPermission.closePeriods);
          final rows = await txn.query(
            'accounting_periods',
            where: 'id = ?',
            whereArgs: [periodId],
            limit: 1,
          );
          if (rows.isEmpty) throw StateError('الفترة المالية غير موجودة');
          final period = rows.single;
          if (period['status'] != 'open') {
            throw StateError('الفترة المالية ليست مفتوحة');
          }
          final invalidEntries = await txn.rawQuery(
            '''
            SELECT je.id FROM journal_entries je
            WHERE substr(je.entry_date, 1, 10) BETWEEN ? AND ?
              AND (
                ABS(COALESCE(je.base_debit_total, je.debit_total) -
                    COALESCE(je.base_credit_total, je.credit_total)) > ?
                OR NOT EXISTS (
                  SELECT 1 FROM journal_lines jl WHERE jl.journal_entry_id = je.id
                )
                OR ABS(
                  (SELECT COALESCE(SUM(COALESCE(jl.base_debit, jl.debit)), 0)
                   FROM journal_lines jl WHERE jl.journal_entry_id = je.id)
                  - COALESCE(je.base_debit_total, je.debit_total)
                ) > ?
                OR ABS(
                  (SELECT COALESCE(SUM(COALESCE(jl.base_credit, jl.credit)), 0)
                   FROM journal_lines jl WHERE jl.journal_entry_id = je.id)
                  - COALESCE(je.base_credit_total, je.credit_total)
                ) > ?
              )
            LIMIT 1
            ''',
            [
              period['start_date'],
              period['end_date'],
              accountingTolerance,
              accountingTolerance,
              accountingTolerance
            ],
          );
          if (invalidEntries.isNotEmpty) {
            throw StateError(
              'لا يمكن إغلاق الفترة؛ يوجد قيد غير مكتمل أو غير متزن',
            );
          }
          final contexts = await txn.query(
            'audit_context',
            columns: ['actor_id'],
            where: 'id = ?',
            whereArgs: [1],
            limit: 1,
          );
          await txn.update(
            'accounting_periods',
            {
              'status': 'closed',
              'closed_at': DateTime.now().toUtc().toIso8601String(),
              'closed_by': contexts.isEmpty
                  ? 'local-owner'
                  : contexts.single['actor_id'],
            },
            where: 'id = ? AND status = ?',
            whereArgs: [periodId, 'open'],
          );
        });
      });

  Future<List<Map<String, Object?>>> periods() async {
    final db = await LocalDatabase.instance.database;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    return db.query(
      'accounting_periods',
      orderBy: 'start_date DESC, id DESC',
    );
  }
}
