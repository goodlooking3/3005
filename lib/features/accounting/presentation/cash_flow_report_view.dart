import 'package:flutter/material.dart';

import '../../../services/report_service.dart';

class CashFlowReportView extends StatelessWidget {
  final List<CashFlowRow> rows;
  final CashFlowReconciliation? reconciliation;

  const CashFlowReportView({
    super.key,
    required this.rows,
    this.reconciliation,
  });

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final row in rows.where((item) => item.category != 'internal_transfer')) {
      final signed = row.direction == 'in' ? row.amount : -row.amount;
      totals.update(row.category, (value) => value + signed,
          ifAbsent: () => signed);
    }
    return ListView(
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('حركة نقد مصنفة داخليًا'),
            subtitle: Text(
              'عرض تشغيلي مشتق من قيود الأستاذ، وليس قائمة IAS 7 معتمدة. التحويلات الداخلية لا تدخل في المجاميع المصنفة؛ وتظهر الأرصدة غير المصنفة صراحةً.',
            ),
          ),
        ),
        if (reconciliation != null)
          Card(
            color: reconciliation!.reconciled
                ? const Color(0xFFE8F8F0)
                : const Color(0xFFFFE8E8),
            child: ListTile(
              leading: Icon(reconciliation!.reconciled
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined),
              title: Text('مصالحة حركة النقد · ${reconciliation!.currency}'),
              subtitle: Text(
                'أول المدة ${reconciliation!.openingBalance.toStringAsFixed(2)} · '
                'صافي حركة الدفتر ${reconciliation!.netLedgerMovement.toStringAsFixed(2)} · '
                'آخر المدة ${reconciliation!.endingBalance.toStringAsFixed(2)}',
              ),
              trailing: Text(
                reconciliation!.reconciled
                    ? 'مطابق'
                    : 'فرق ${reconciliation!.difference.toStringAsFixed(2)}',
              ),
            ),
          ),
        for (final category in ['operating', 'investing', 'financing', 'unclassified'])
          if (totals.containsKey(category))
            Card(
              child: ListTile(
                title: Text(_label(category)),
                trailing: Text(totals[category]!.toStringAsFixed(2)),
              ),
            ),
        if (rows.isEmpty)
          const Center(child: Text('لا توجد حركات نقدية ضمن الفلاتر.'))
        else ...[
          const Divider(),
          ...rows.map((row) => ListTile(
              leading: Icon(row.category == 'internal_transfer'
                  ? Icons.swap_horiz_rounded
                  : row.direction == 'in'
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded),
              title: Text(row.description),
              subtitle: Text(
                '${_label(row.category)} · ${row.date.substring(0, 10)}',
              ),
              trailing: Text(
                '${row.direction == 'in' ? '+' : '−'}${row.amount.toStringAsFixed(2)}',
              ),
            )),
        ],
      ],
    );
  }

  String _label(String category) => switch (category) {
        'operating' => 'تشغيلي',
        'investing' => 'استثماري',
        'financing' => 'تمويلي',
        'internal_transfer' => 'تحويل داخلي — مستبعد من المجاميع المصنفة',
        _ => 'غير مصنف',
      };
}
