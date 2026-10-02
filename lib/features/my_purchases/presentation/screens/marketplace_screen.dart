import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../../core/production_config.dart';
import '../../data/datasources/local_vendors_db.dart';
import '../../data/purchase_engine.dart';
import '../../domain/vendor_model.dart';
import '../widgets/product_card.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});
  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final db = LocalVendorsDb();
  final engine = PurchaseEngine();
  String category = 'الكل';
  Vendor? vendor;
  List<Vendor> vendors = [];
  List<MarketplaceProduct> products = [];
  final cart = <PurchaseCartLine>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb && ProductionConfig.webReviewMode) await db.seedIfEmpty();
    final loaded = await db.vendors(category: category);
    var selectedVendor = loaded.isEmpty ? null : loaded.first;
    var selectedProducts = <MarketplaceProduct>[];
    for (final candidate in loaded) {
      final id = candidate.id;
      if (id == null) continue;
      final items = await db.products(id);
      if (items.isNotEmpty) {
        selectedVendor = candidate;
        selectedProducts = items;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      vendors = loaded;
      vendor = selectedVendor;
      products = selectedProducts;
    });
  }

  Future<void> _selectVendor(Vendor item) async {
    setState(() {
      vendor = item;
      products = [];
    });
    final items = await db.products(item.id!);
    if (mounted) setState(() => products = items);
  }

  void _add(MarketplaceProduct product) => setState(() {
        final index = cart.indexWhere((line) => line.product.id == product.id);
        if (index == -1) {
          cart.add(PurchaseCartLine(product: product));
        } else {
          cart[index] = PurchaseCartLine(
              product: product, quantity: cart[index].quantity + 1);
        }
      });

  Future<void> _checkout() async {
    if (vendor == null || cart.isEmpty) return;
    final receipt = await engine.checkout(
        vendor: vendor!,
        cart: PurchaseCart(List.of(cart)),
        walletName: 'محفظتي',
        walletAccount: 'محفظتي');
    if (!mounted) return;
    setState(() => cart.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم تسجيل ${receipt.order.number} وترحيله محاسبيًا')));
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in VendorCategory.values)
                ChoiceChip(
                  label: Text(item),
                  selected: category == item,
                  onSelected: (_) {
                    setState(() => category = item);
                    _load();
                  },
                ),
              OutlinedButton.icon(
                onPressed: _addVendor,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('مورد'),
              ),
              OutlinedButton.icon(
                onPressed: vendor == null ? null : _addProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('منتج'),
              ),
              FilledButton.icon(
                onPressed: cart.isEmpty ? null : _checkout,
                icon: const Icon(Icons.account_balance_wallet),
                label: Text('السلة (${cart.length})'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
              height: 82,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: vendors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, index) {
                    final item = vendors[index];
                    return ChoiceChip(
                        label: Text(item.name),
                        selected: vendor?.id == item.id,
                        onSelected: (_) => _selectVendor(item));
                  })),
          const SizedBox(height: 12),
          Expanded(
              child: products.isEmpty
                  ? const Center(child: Text('لا توجد منتجات متاحة'))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 250,
                              mainAxisExtent: 300,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12),
                      itemCount: products.length,
                      itemBuilder: (_, index) => ProductCard(
                          product: products[index],
                          onAdd: () => _add(products[index])))),
        ],
      );

  Future<void> _addVendor() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var categoryValue = VendorCategory.values[1];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة مورد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم المورد')),
            TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف')),
            DropdownButtonFormField<String>(
              initialValue: categoryValue,
              decoration: const InputDecoration(labelText: 'التصنيف'),
              items: VendorCategory.values
                  .skip(1)
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) => categoryValue = value ?? categoryValue,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await db.saveVendor(Vendor(
                  name: name.text.trim(),
                  category: categoryValue,
                  phone: phone.text.trim()));
              await _load();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ المورد'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
  }

  Future<void> _addProduct() async {
    final selectedVendor = vendor;
    if (selectedVendor?.id == null) return;
    final name = TextEditingController();
    final categoryController =
        TextEditingController(text: selectedVendor!.category);
    final price = TextEditingController();
    var currency = 'SAR';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إضافة منتج لدى ${selectedVendor.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم المنتج')),
            TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'التصنيف')),
            TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'السعر')),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: const ['SAR', 'USD', 'YER']
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) => currency = value ?? 'SAR',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final value =
                  double.tryParse(price.text.replaceAll(',', '')) ?? 0;
              if (name.text.trim().isEmpty || value <= 0) return;
              await db.saveProduct(MarketplaceProduct(
                  vendorId: selectedVendor.id!,
                  inventoryItemId: null,
                  name: name.text.trim(),
                  category: categoryController.text.trim(),
                  price: value,
                  currency: currency));
              await _selectVendor(selectedVendor);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ المنتج'),
          ),
        ],
      ),
    );
    name.dispose();
    categoryController.dispose();
    price.dispose();
  }
}
