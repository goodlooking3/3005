import 'package:flutter/material.dart';

import '../../domain/vendor_model.dart';

Future<List<PurchaseCartLine>?> showPurchaseCartDialog({
  required BuildContext context,
  required List<PurchaseCartLine> lines,
}) async {
  final editedLines = List<PurchaseCartLine>.of(lines);
  final currency = lines.isEmpty ? '' : lines.first.product.currency;

  return showDialog<List<PurchaseCartLine>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final subtotal = editedLines.fold<double>(
          0,
          (sum, line) => sum + line.total,
        );
        return AlertDialog(
          title: const Text('مراجعة سلة الشراء'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: editedLines.isEmpty
                ? const Center(child: Text('السلة فارغة'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: editedLines.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (_, index) {
                      final line = editedLines[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${line.product.price.toStringAsFixed(2)} $currency × ${line.quantity} = ${line.total.toStringAsFixed(2)} $currency',
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'تقليل الكمية',
                                onPressed: line.quantity <= 1
                                    ? null
                                    : () => setDialogState(() {
                                          editedLines[index] = PurchaseCartLine(
                                            product: line.product,
                                            quantity: line.quantity - 1,
                                          );
                                        }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('${line.quantity}'),
                              IconButton(
                                tooltip: 'زيادة الكمية',
                                onPressed: () => setDialogState(() {
                                  editedLines[index] = PurchaseCartLine(
                                    product: line.product,
                                    quantity: line.quantity + 1,
                                  );
                                }),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'حذف الصنف',
                                onPressed: () => setDialogState(
                                  () => editedLines.removeAt(index),
                                ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            Text(
              'المجموع الفرعي: ${subtotal.toStringAsFixed(2)} $currency',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: editedLines.isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        List<PurchaseCartLine>.unmodifiable(editedLines),
                      ),
              child: const Text('متابعة للتسويات'),
            ),
          ],
        );
      },
    ),
  );
}
