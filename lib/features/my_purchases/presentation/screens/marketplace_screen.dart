import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../../core/production_config.dart';
import '../../data/datasources/local_vendors_db.dart';
import '../../data/purchase_engine.dart';
import '../../domain/vendor_model.dart';
import '../widgets/marketplace_product_list.dart';
import '../widgets/purchase_adjustments_dialog.dart';
import '../widgets/purchase_cart_dialog.dart';

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
  bool _loading = false;
  bool _checkingOut = false;
  String? _error;
  int? _cartVendorId;
  int _vendorLoadRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_vendorLoadRequest;
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      if (kIsWeb && ProductionConfig.webReviewMode) await db.seedIfEmpty();
      final loaded = await db.vendors(category: category);
      var selectedVendor = loaded.isEmpty ? null : loaded.first;
      var selectedProducts = <MarketplaceProduct>[];
      final currentId = vendor?.id;
      if (currentId != null) {
        for (final candidate in loaded) {
          if (candidate.id == currentId) {
            selectedVendor = candidate;
            selectedProducts = await db.products(currentId);
            break;
          }
        }
      }
      if (selectedProducts.isEmpty && cart.isEmpty) {
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
      }
      if (!mounted || request != _vendorLoadRequest) return;
      setState(() {
        vendors = loaded;
        vendor = selectedVendor;
        products = selectedProducts;
      });
    } catch (_) {
      if (mounted && request == _vendorLoadRequest) {
        setState(() => _error = 'تعذر تحميل الموردين والمنتجات');
      }
    } finally {
      if (mounted && request == _vendorLoadRequest) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectVendor(Vendor item) async {
    if (_checkingOut || _loading) return;
    if (cart.isNotEmpty &&
        (vendor?.id != item.id || _cartVendorId != item.id)) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تغيير المورد'),
          content: const Text(
            'سيؤدي تغيير المورد إلى إفراغ سلة الشراء الحالية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إبقاء السلة'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إفراغ وتغيير'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      setState(() {
        cart.clear();
        _cartVendorId = null;
      });
    }
    final request = ++_vendorLoadRequest;
    setState(() {
      vendor = item;
      products = [];
    });
    try {
      final items = await db.products(item.id!);
      if (mounted && request == _vendorLoadRequest && vendor?.id == item.id) {
        setState(() => products = items);
      }
    } catch (_) {
      if (mounted && request == _vendorLoadRequest) {
        setState(() => _error = 'تعذر تحميل منتجات المورد');
      }
    }
  }

  void _add(MarketplaceProduct product) {
    if (vendor?.id == null || product.vendorId != vendor!.id) {
      _showMessage('لا يمكن إضافة منتج تابع لمورد آخر');
      return;
    }
    if (cart.isNotEmpty && _cartVendorId != vendor!.id) {
      _showMessage('أفرغ السلة قبل تغيير المورد');
      return;
    }
    if (cart.isNotEmpty &&
        cart.first.product.currency.trim().toUpperCase() !=
            product.currency.trim().toUpperCase()) {
      _showMessage('لا يمكن جمع عملات مختلفة في سلة شراء واحدة');
      return;
    }
    setState(() {
      _cartVendorId ??= vendor!.id;
      final index = cart.indexWhere((line) => line.product.id == product.id);
      if (index == -1) {
        cart.add(PurchaseCartLine(product: product));
      } else {
        cart[index] = PurchaseCartLine(
          product: product,
          quantity: cart[index].quantity + 1,
        );
      }
    });
  }

  Future<void> _checkout() async {
    if (vendor == null || cart.isEmpty || _checkingOut) return;
    if (_cartVendorId != vendor!.id) {
      _showMessage('لا تتطابق السلة مع المورد المحدد؛ أفرغها ثم حاول مجددًا');
      return;
    }
    setState(() {
      _checkingOut = true;
      _error = null;
    });
    try {
      final reviewedLines = await showPurchaseCartDialog(
        context: context,
        lines: cart,
      );
      if (reviewedLines == null || reviewedLines.isEmpty) return;
      if (!mounted) return;
      setState(() {
        cart
          ..clear()
          ..addAll(reviewedLines);
      });
      final adjustments = await showPurchaseAdjustmentsDialog(
        context: context,
        lines: cart,
      );
      if (adjustments == null) return;
      final receipt = await engine.checkout(
        vendor: vendor!,
        cart: PurchaseCart(List.of(cart), adjustments: adjustments),
        walletName: 'محفظتي',
        walletAccount: 'محفظتي',
      );
      if (!mounted) return;
      setState(() {
        cart.clear();
        _cartVendorId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تسجيل ${receipt.order.number} وترحيله محاسبيًا'),
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() => _error = 'تعذر إتمام الشراء؛ لم تُحفظ تغييرات جزئية');
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _changeCategory(String value) async {
    if (_checkingOut || value == category) return;
    final changesVendor = value != 'الكل' && vendor?.category != value;
    if (changesVendor && cart.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تغيير التصنيف'),
          content: const Text(
            'سيؤدي اختيار تصنيف لمورد آخر إلى إفراغ سلة الشراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إبقاء السلة'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إفراغ ومتابعة'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      setState(() {
        cart.clear();
        _cartVendorId = null;
      });
    }
    if (!mounted) return;
    setState(() => category = value);
    _load();
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

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
                  onSelected:
                      _checkingOut ? null : (_) => _changeCategory(item),
                ),
              OutlinedButton.icon(
                onPressed: _loading || _checkingOut ? null : _addVendor,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('مورد'),
              ),
              OutlinedButton.icon(
                onPressed: vendor == null || _loading || _checkingOut
                    ? null
                    : _addProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('منتج'),
              ),
              FilledButton.icon(
                onPressed: cart.isEmpty || _checkingOut ? null : _checkout,
                icon: const Icon(Icons.account_balance_wallet),
                label: Text(
                  _checkingOut
                      ? 'جارٍ الحفظ…'
                      : 'السلة (${cart.length} | ${cart.fold<double>(0, (sum, item) => sum + item.quantity)} قطعة) — ${cart.isEmpty ? '0.00' : cart.fold<double>(0, (sum, item) => sum + item.total).toStringAsFixed(2)} ${cart.isEmpty ? '' : cart.first.product.currency}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'إعادة المحاولة',
                ),
              ),
            ),
          if (_loading && products.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
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
                    onSelected: _checkingOut || _loading
                        ? null
                        : (_) => _selectVendor(item),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('لا توجد منتجات متاحة'))
                : MarketplaceProductList(
                    key: ValueKey(vendor?.id),
                    products: products,
                    onAdd: _add,
                  ),
          ),
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
              decoration: const InputDecoration(labelText: 'اسم المورد'),
            ),
            TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
            ),
            DropdownButtonFormField<String>(
              initialValue: categoryValue,
              decoration: const InputDecoration(labelText: 'التصنيف'),
              items: VendorCategory.values
                  .skip(1)
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) => categoryValue = value ?? categoryValue,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await db.saveVendor(
                Vendor(
                  name: name.text.trim(),
                  category: categoryValue,
                  phone: phone.text.trim(),
                ),
              );
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
    final categoryController = TextEditingController(
      text: selectedVendor!.category,
    );
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
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
            ),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: 'التصنيف'),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر'),
            ),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: const ['SAR', 'USD', 'YER']
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) => currency = value ?? 'SAR',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final value =
                  double.tryParse(price.text.replaceAll(',', '')) ?? 0;
              if (name.text.trim().isEmpty || value <= 0) return;
              await db.saveProduct(
                MarketplaceProduct(
                  vendorId: selectedVendor.id!,
                  inventoryItemId: null,
                  name: name.text.trim(),
                  category: categoryController.text.trim(),
                  price: value,
                  currency: currency,
                ),
              );
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
