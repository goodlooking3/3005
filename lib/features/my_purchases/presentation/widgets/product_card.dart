import 'package:flutter/material.dart';

import '../../domain/vendor_model.dart';

class ProductCard extends StatelessWidget {
  final MarketplaceProduct product;
  final VoidCallback onAdd;
  const ProductCard({super.key, required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, size: 42, color: Color(0xFF315CFF)),
                ),
              ),
              const SizedBox(height: 10),
              Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${product.price.toStringAsFixed(2)} ${product.currency}', style: const TextStyle(color: Color(0xFF079455), fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add_shopping_cart, size: 17), label: const Text('أضف للسلة'))),
            ],
          ),
        ),
      );
}
