import 'package:flutter/material.dart';

import '../../domain/vendor_model.dart';
import 'product_card.dart';

class MarketplaceProductList extends StatefulWidget {
  final List<MarketplaceProduct> products;
  final ValueChanged<MarketplaceProduct> onAdd;

  const MarketplaceProductList({
    super.key,
    required this.products,
    required this.onAdd,
  });

  @override
  State<MarketplaceProductList> createState() => _MarketplaceProductListState();
}

class _MarketplaceProductListState extends State<MarketplaceProductList> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final visible = widget.products.where((product) {
      return product.name.toLowerCase().contains(normalizedQuery) ||
          product.category.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);

    return Column(
      children: [
        TextField(
          key: const ValueKey('marketplace-product-search'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'بحث عن منتج أو تصنيف',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    normalizedQuery.isEmpty
                        ? 'لا توجد منتجات متاحة'
                        : 'لا توجد منتجات تطابق البحث',
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 250,
                    mainAxisExtent: 300,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, index) => ProductCard(
                    product: visible[index],
                    onAdd: () => widget.onAdd(visible[index]),
                  ),
                ),
        ),
      ],
    );
  }
}
