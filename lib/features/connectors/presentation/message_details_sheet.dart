import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../core/connector_models.dart';

class MessageDetailsSheet extends StatefulWidget {
  final IncomingMessage message;
  final List<String> accountNames;
  final Future<void> Function(
    VoucherType type,
    String debit,
    String credit,
    double amount,
    String currency,
    String description,
  ) onPost;

  const MessageDetailsSheet({
    super.key,
    required this.message,
    required this.accountNames,
    required this.onPost,
  });

  @override
  State<MessageDetailsSheet> createState() => _MessageDetailsSheetState();
}

class _MessageDetailsSheetState extends State<MessageDetailsSheet> {
  late VoucherType type;
  late String debit;
  late String credit;
  late final TextEditingController amountController;
  late final TextEditingController currencyController;
  late final TextEditingController descriptionController;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    type = VoucherType.receipt;
    debit = _pick('الصندوق الرئيسي');
    credit = _pick('إيرادات الخدمات');
    amountController = TextEditingController(
      text: widget.message.parsedAmount?.toStringAsFixed(2) ?? '',
    );
    currencyController = TextEditingController(
      text: widget.message.parsedCurrency ?? 'SAR',
    );
    descriptionController = TextEditingController(
      text:
          'ترحيل رسالة ${widget.message.provider} من ${widget.message.sender}',
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    currencyController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  String _pick(String preferred) => widget.accountNames.contains(preferred)
      ? preferred
      : widget.accountNames.isEmpty
          ? preferred
          : widget.accountNames.first;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return AlertDialog(
      title: const Text('معاينة الرسالة'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detail('المصدر', message.provider),
              _detail('المرسل', message.sender),
              if (message.senderPhone != null)
                _detail('الهاتف', message.senderPhone!),
              _detail('تاريخ الاستلام', message.receivedAt.toString()),
              _detail(
                'المبلغ',
                '${message.parsedAmount?.toStringAsFixed(2) ?? 'غير مستخرج'} ${message.parsedCurrency ?? ''}',
              ),
              if (message.reference != null)
                _detail('المرجع', message.reference!),
              const Divider(height: 28),
              const Text(
                'نص الرسالة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SelectableText(message.body),
              const Divider(height: 28),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ المعتمد'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: currencyController,
                decoration: const InputDecoration(labelText: 'العملة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'وصف الحركة'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<VoucherType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'نوع الحركة'),
                items: const [
                  DropdownMenuItem(
                    value: VoucherType.receipt,
                    child: Text('سند قبض'),
                  ),
                  DropdownMenuItem(
                    value: VoucherType.payment,
                    child: Text('سند صرف'),
                  ),
                  DropdownMenuItem(
                    value: VoucherType.journal,
                    child: Text('قيد يومي'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) =>
                        setState(() => type = value ?? VoucherType.receipt),
              ),
              const SizedBox(height: 10),
              _accountField('الحساب المدين', debit, (value) => debit = value),
              const SizedBox(height: 10),
              _accountField('الحساب الدائن', credit, (value) => credit = value),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : _post,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.post_add_rounded),
          label: const Text('ترحيل محاسبي'),
        ),
      ],
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 105,
              child: Text(label,
                  style: TextStyle(color: Colors.blueGrey.shade500)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _accountField(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: (widget.accountNames.isEmpty ? [value] : widget.accountNames)
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged:
            saving ? null : (item) => setState(() => onChanged(item ?? value)),
      );

  Future<void> _post() async {
    final amount = double.tryParse(
      amountController.text.trim().replaceAll(',', ''),
    );
    if (amount == null ||
        amount <= 0 ||
        currencyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل مبلغًا وعملة صالحين')));
      return;
    }
    setState(() => saving = true);
    try {
      await widget.onPost(
        type,
        debit,
        credit,
        amount,
        currencyController.text,
        descriptionController.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      setState(() => saving = false);
    }
  }
}
