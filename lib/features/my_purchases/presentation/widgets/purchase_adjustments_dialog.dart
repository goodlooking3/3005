import 'package:flutter/material.dart';

import '../../domain/vendor_model.dart';

Future<PurchaseAdjustments?> showPurchaseAdjustmentsDialog({
  required BuildContext context,
  required List<PurchaseCartLine> lines,
}) async {
  final shipping = TextEditingController();
  final discount = TextEditingController();
  final subtotal = lines.fold<double>(0, (sum, line) => sum + line.total);
  final currency = lines.isEmpty ? '' : lines.first.product.currency;
  String? validationError;

  PurchaseAdjustments? parsedAdjustments() => PurchaseAdjustments.tryParse(
        shipping: shipping.text,
        discount: discount.text,
        recoverableTax: '0',
        nonRecoverableTax: '0',
        subtotal: subtotal,
      );

  final result = await showDialog<PurchaseAdjustments>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final preview = parsedAdjustments();
        final total = preview == null
            ? null
            : subtotal - preview.discount + preview.shipping + preview.totalTax;
        return AlertDialog(
          title: const Text('تسويات الشراء'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in [
                  (shipping, 'الشحن والتكاليف الواردة'),
                  (discount, 'الخصم التجاري'),
                ])
                  TextField(
                    controller: entry.$1,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: entry.$2,
                      suffixText: currency,
                    ),
                    onChanged: (_) => setDialogState(() {
                      validationError = null;
                    }),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'الضرائب معطلة حتى ضبط سياسة بلد المنشأة؛ لا تُفترض معدلات أو حسابات ضريبية.',
                  ),
                ),
                if (total != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'الإجمالي بعد التسويات: ${total.toStringAsFixed(2)} $currency',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      validationError!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final adjustments = parsedAdjustments();
                if (adjustments == null) {
                  setDialogState(() => validationError =
                      'أدخل مبالغ رقمية موجبة أو صفرًا، واجعل الخصم ضمن قيمة السلة');
                  return;
                }
                Navigator.pop(dialogContext, adjustments);
              },
              child: const Text('متابعة'),
            ),
          ],
        );
      },
    ),
  );
  shipping.dispose();
  discount.dispose();
  return result;
}
