import 'package:flutter/material.dart';

import '../../data/datasources/inventory_local_db.dart';
import '../../domain/inventory_item.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final sku = TextEditingController();
  final cost = TextEditingController();
  final sale = TextEditingController();
  final quantity = TextEditingController();
  final threshold = TextEditingController(text: '5');

  @override
  void dispose() { name.dispose(); sku.dispose(); cost.dispose(); sale.dispose(); quantity.dispose(); threshold.dispose(); super.dispose(); }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    await InventoryLocalDb().save(InventoryItem(name: name.text.trim(), sku: sku.text.trim(), costPrice: double.parse(cost.text), salePrice: double.parse(sale.text), quantity: double.parse(quantity.text), lowStockThreshold: double.parse(threshold.text)));
    if (mounted) Navigator.pop(context);
  }

  String? requiredNumber(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || !number.isFinite || number < 0
        ? 'أدخل رقمًا صحيحًا غير سالب'
        : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('إضافة منتج')), body: Form(key: formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج'), validator: (v) => v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null),
        TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'الباركود / SKU')),
        TextFormField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر التكلفة'), validator: requiredNumber),
        TextFormField(controller: sale, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع'), validator: requiredNumber),
        TextFormField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية المتوفرة'), validator: requiredNumber),
        TextFormField(controller: threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد التنبيه'), validator: requiredNumber),
        const SizedBox(height: 22),
        FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('حفظ المنتج')),
      ])));
}
