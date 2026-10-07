import 'package:flutter/material.dart';

import '../../../services/report_service.dart';

class FinancialPositionSection extends StatelessWidget {
  final String title;
  final List<FinancialPositionLine> rows;
  final double total;

  const FinancialPositionSection({
    super.key,
    required this.title,
    required this.rows,
    required this.total,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          title: Text(title),
          subtitle: Text('الإجمالي ${total.toStringAsFixed(2)}'),
          children: rows.isEmpty
              ? const [ListTile(title: Text('لا توجد أرصدة.'))]
              : [
                  for (final classification in [
                    'current',
                    'non_current',
                    'unclassified',
                  ])
                    if (rows.any((row) => row.positionClass == classification))
                      ExpansionTile(
                        title: Text(_label(classification)),
                        subtitle: Text(
                          rows
                              .where((row) =>
                                  row.positionClass == classification)
                              .fold<double>(0, (sum, row) => sum + row.balance)
                              .toStringAsFixed(2),
                        ),
                        children: rows
                            .where((row) =>
                                row.positionClass == classification)
                            .map((row) => ListTile(
                                  title: Text(row.account),
                                  subtitle: Text(row.code),
                                  trailing:
                                      Text(row.balance.toStringAsFixed(2)),
                                ))
                            .toList(),
                      ),
                ],
        ),
      );

  String _label(String value) => switch (value) {
        'current' => 'جاري',
        'non_current' => 'غير جاري',
        _ => 'غير مصنف',
      };
}
