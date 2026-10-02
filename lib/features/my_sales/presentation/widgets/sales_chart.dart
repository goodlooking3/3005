import 'package:flutter/material.dart';

class SalesChart extends StatelessWidget {
  final Map<String, double> values;
  const SalesChart({super.key, required this.values});

  String _label(String key) => switch (key) {
        'sales' => 'المبيعات',
        'costs' => 'التكلفة',
        'profit' => 'صافي الربح',
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    final max = values.values.fold<double>(1, (a, b) => a > b ? a : b);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('أداء المبيعات',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          ...values.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                SizedBox(width: 86, child: Text(_label(entry.key))),
                Expanded(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                            minHeight: 12,
                            value: (entry.value / max).clamp(0, 1),
                            color: const Color(0xFF315CFF),
                            backgroundColor: const Color(0xFFE7EBF2)))),
                const SizedBox(width: 10),
                Text(entry.value.toStringAsFixed(2))
              ]))),
        ]),
      ),
    );
  }
}
