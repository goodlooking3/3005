import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../../core/production_config.dart';
import '../../data/datasources/inventory_local_db.dart';
import '../../data/sales_engine.dart';
import '../../domain/inventory_item.dart';
import '../widgets/sales_chart.dart';
import 'add_product_screen.dart';
import 'inventory_movements_screen.dart';
import 'sales_reversals_screen.dart';
import 'sales_invoice_screen.dart';

class MySalesDashboard extends StatefulWidget {
  const MySalesDashboard({super.key});
  @override
  State<MySalesDashboard> createState() => _MySalesDashboardState();
}

class _MySalesDashboardState extends State<MySalesDashboard> {
  final inventory = InventoryLocalDb();
  final sales = SalesEngine();
  List<InventoryItem> items = [];
  Map<String, double> summary = {'sales': 0, 'costs': 0, 'profit': 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb && ProductionConfig.webReviewMode) {
      await inventory.seedIfEmpty();
    }
    final loaded = await inventory.items();
    final totals = await sales.summary();
    if (mounted)
      setState(() {
        items = loaded;
        summary = totals;
      });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              SizedBox(
                width: constraints.maxWidth > 520
                    ? constraints.maxWidth * .65
                    : constraints.maxWidth,
                child: const Text(
                  'إدارة المنتجات والمخزون',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddProductScreen(),
                    ),
                  );
                  _load();
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة منتج'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InventoryMovementsScreen())),
            icon: const Icon(Icons.timeline_rounded),
            label: const Text('سجل الحركات'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SalesReversalsScreen())),
            icon: const Icon(Icons.swap_horizontal_circle_outlined),
            label: const Text('المرتجعات والإلغاء'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SalesInvoiceScreen()));
              _load();
            },
            icon: const Icon(Icons.point_of_sale),
            label: const Text('فاتورة بيع'),
          ),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 2;
            final width =
                (constraints.maxWidth - ((columns - 1) * 10)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ['sales', 'costs', 'profit']
                  .map((key) => SizedBox(
                        width: width,
                        child: Card(
                            elevation: 0,
                            child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(key == 'sales'
                                          ? 'إجمالي المبيعات'
                                          : key == 'costs'
                                              ? 'تكلفة البضاعة'
                                              : 'صافي الأرباح'),
                                      const SizedBox(height: 8),
                                      Text(summary[key]!.toStringAsFixed(2),
                                          style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.bold))
                                    ]))),
                      ))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        SalesChart(values: summary),
        const SizedBox(height: 16),
        const Text('المخزون الحالي',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('لا توجد منتجات بعد. أضف منتجًا لبدء إدارة مخزونك.'),
            ),
          ),
        ...items.map((item) => Card(
            elevation: 0,
            child: ListTile(
                leading: CircleAvatar(child: Text(item.name.characters.first)),
                title: Text(item.name),
                subtitle: Text(
                    'SKU: ${item.sku}  •  بيع ${item.salePrice.toStringAsFixed(2)} ${item.currency}'),
                trailing: Text(
                    '${item.quantity.toStringAsFixed(0)} ${item.lowStock ? '⚠ منخفض' : 'متوفر'}',
                    style: TextStyle(
                        color: item.lowStock ? Colors.orange : Colors.green,
                        fontWeight: FontWeight.bold))))),
      ]));
}
