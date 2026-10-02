import 'package:flutter/material.dart';

import '../../domain/models/wallet_model.dart';

class TransferDialog extends StatefulWidget {
  final List<Wallet> wallets;
  final Future<void> Function(
    WalletAccount from,
    WalletAccount to,
    double amount,
    String currency,
    String note,
  ) onSubmit;
  const TransferDialog({
    super.key,
    required this.wallets,
    required this.onSubmit,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final amount = TextEditingController();
  final note = TextEditingController();
  final currencyController = TextEditingController(text: 'SAR');
  String? fromKey;
  String? toKey;

  Map<String, WalletAccount> get accountOptions => {
        for (final wallet in widget.wallets)
          for (final account in wallet.accounts)
            '${wallet.name} / ${account.name} (${account.currency})': account,
      };

  @override
  void initState() {
    super.initState();
    final keys = accountOptions.keys.toList();
    if (keys.isNotEmpty) fromKey = keys.first;
    if (keys.length > 1) toKey = keys[1];
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = accountOptions;
    return AlertDialog(
      title: const Text('تحويل سريع'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: fromKey,
              decoration: const InputDecoration(labelText: 'من الحساب'),
              items: options.keys.map(_item).toList(),
              onChanged: (value) => setState(() => fromKey = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: toKey,
              decoration: const InputDecoration(labelText: 'إلى الحساب'),
              items: options.keys.map(_item).toList(),
              onChanged: (value) => setState(() => toKey = value),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
            TextField(
              controller: currencyController,
              decoration: const InputDecoration(labelText: 'العملة'),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'البيان (اختياري)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('مراجعة التحويل')),
      ],
    );
  }

  DropdownMenuItem<String> _item(String value) =>
      DropdownMenuItem(value: value, child: Text(value));

  Future<void> _submit() async {
    final value = double.tryParse(amount.text.replaceAll(',', '').trim());
    final options = accountOptions;
    final from = fromKey == null ? null : options[fromKey];
    final to = toKey == null ? null : options[toKey];
    if (from == null ||
        to == null ||
        from.id == to.id ||
        value == null ||
        value <= 0) {
      return;
    }
    await widget.onSubmit(
      from,
      to,
      value,
      currencyController.text.trim().isEmpty
          ? from.currency
          : currencyController.text.trim().toUpperCase(),
      note.text.trim(),
    );
    if (mounted) Navigator.pop(context);
  }
}
