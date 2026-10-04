import 'package:flutter/material.dart';

import '../../data/datasources/inventory_local_db.dart';
import '../../data/sales_engine.dart';
import '../../domain/inventory_item.dart';
import '../../domain/inventory_movement.dart';

class InventoryMovementsScreen extends StatefulWidget {
  const InventoryMovementsScreen({super.key});

  @override
  State<InventoryMovementsScreen> createState() => _InventoryMovementsScreenState();
}

class _InventoryMovementsScreenState extends State<InventoryMovementsScreen> {
  final engine = SalesEngine();
  final inventory = InventoryLocalDb();
  List<InventoryItem> items = [];
  List<InventoryMovement> movements = [];
  int? selectedItem;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final loadedItems = await inventory.items(activeOnly: false);
      final loadedMovements = await engine.movements(itemId: selectedItem);
      if (mounted) setState(() { items = loadedItems; movements = loadedMovements; loading = false; });
    } catch (value) {
      if (mounted) setState(() { loading = false; error = 'تعذر تحميل حركات المخزون: $value'; });
    }
  }

  Color _movementColor(String type) => switch (type) {
        'sale' => const Color(0xFFB42318),
        'return' => const Color(0xFF027A48),
        'cancellation' => const Color(0xFFB54708),
        _ => const Color(0xFF315CFF),
      };

  String _movementLabel(String type) => switch (type) {
        'sale' => 'بيع',
        'return' => 'مرتجع',
        'cancellation' => 'إلغاء',
        _ => type,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('سجل حركات المخزون'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _summaryCard(),
              if (error != null) Card(color: Colors.red.shade50, child: ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text(error!),
                trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              )),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                value: selectedItem,
                decoration: const InputDecoration(labelText: 'تصفية حسب الصنف', prefixIcon: Icon(Icons.inventory_2_outlined)),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل الأصناف')),
                  ...items.where((item) => item.id != null).map((item) => DropdownMenuItem<int?>(value: item.id, child: Text(item.name))),
                ],
                onChanged: (value) {
                  selectedItem = value;
                  _load();
                },
              ),
              const SizedBox(height: 18),
              if (loading)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
              else if (movements.isEmpty)
                _emptyState()
              else
                ...movements.map(_movementCard),
            ],
          ),
        ),
      );

  Widget _summaryCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF172554), Color(0xFF315CFF)]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.timeline_rounded, color: Colors.white)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('أثر المخزون', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 5),
              Text('${movements.length} حركة مسجلة', style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            ])),
            Text(selectedItem == null ? 'الكل' : 'صنف محدد', style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Widget _movementCard(InventoryMovement movement) {
    final color = _movementColor(movement.movementType);
    final signed = movement.quantity > 0 ? '+${movement.quantity}' : '${movement.quantity}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: CircleAvatar(backgroundColor: color.withAlpha(24), child: Icon(movement.quantity > 0 ? Icons.south_west_rounded : Icons.north_east_rounded, color: color)),
        title: Row(children: [Text(_movementLabel(movement.movementType), style: TextStyle(color: color, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Expanded(child: Text(movement.referenceId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))]),
        subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text('${_date(movement.createdAt)}  •  الرصيد بعد الحركة: ${movement.balanceAfter.toStringAsFixed(2)}\n${movement.note}', maxLines: 2, overflow: TextOverflow.ellipsis)),
        trailing: Text(signed, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _emptyState() => Card(child: Padding(padding: const EdgeInsets.all(30), child: Column(children: const [Icon(Icons.receipt_long_outlined, size: 42, color: Colors.blueGrey), SizedBox(height: 12), Text('لا توجد حركات مسجلة بعد'), SizedBox(height: 4), Text('ستظهر هنا عمليات البيع والمرتجعات والإلغاءات.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey))])));

  String _date(DateTime value) => '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}
