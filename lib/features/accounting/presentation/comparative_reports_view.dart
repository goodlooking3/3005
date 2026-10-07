import 'package:flutter/material.dart';

import '../../../services/report_service.dart';

class ComparativeProfitLossSummary extends StatelessWidget {
  final ProfitLossReport report;
  final DateTime from;
  final DateTime to;

  const ComparativeProfitLossSummary({
    super.key,
    required this.report,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: const Text('الفترة المقارنة السابقة'),
          subtitle: Text(
            '${_date(from)} – ${_date(to)}\n'
            'الإيرادات ${report.revenue.toStringAsFixed(2)} · '
            'المصروفات ${report.expenses.toStringAsFixed(2)}',
          ),
          trailing: Text('الصافي ${report.net.toStringAsFixed(2)}'),
        ),
      );
}

class ComparativeBalanceSheetSummary extends StatelessWidget {
  final BalanceSheetReport report;

  const ComparativeBalanceSheetSummary({
    super.key,
    required this.report,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text('مقارنة كما في ${_date(report.asOf)}'),
          subtitle: Text(
            'الأصول ${report.assets.toStringAsFixed(2)} · '
            'الالتزامات ${report.liabilities.toStringAsFixed(2)} · '
            'حقوق الملكية ${report.equity.toStringAsFixed(2)}',
          ),
          trailing: Text(report.isBalanced ? 'متوازن' : 'فرق ظاهر'),
        ),
      );
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
