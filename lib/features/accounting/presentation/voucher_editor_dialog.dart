import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../core/user_facing_errors.dart';
import '../../../data/accounting_repository.dart';
import 'account_picker_fields.dart';

class VoucherEditorDialog extends StatefulWidget {
  final AccountingRepository repository;
  final VoucherType type;
  final List<Account> accounts;
  final List<Party> parties;
  const VoucherEditorDialog(
      {super.key,
      required this.repository,
      required this.type,
      required this.accounts,
      required this.parties});
  @override
  State<VoucherEditorDialog> createState() => _VoucherEditorDialogState();
}

class _VoucherEditorDialogState extends State<VoucherEditorDialog> {
  final number = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  final debitAmount = TextEditingController();
  final creditAmount = TextEditingController();
  Account? debit;
  Account? credit;
  Party? party;
  String debitCurrency = 'SAR';
  String creditCurrency = 'SAR';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    number.text =
        '${widget.type.name.substring(0, 2).toUpperCase()}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    if (widget.accounts.length > 1) {
      debit = widget.accounts.first;
      credit = widget.accounts[1];
      debitCurrency = debit!.supportedCurrencies.first;
      creditCurrency = credit!.supportedCurrencies.first;
    }
    if (widget.parties.isNotEmpty) party = widget.parties.first;
  }

  @override
  void dispose() {
    number.dispose();
    description.dispose();
    amount.dispose();
    debitAmount.dispose();
    creditAmount.dispose();
    super.dispose();
  }

  List<String> _currencies(Account? account) =>
      account?.supportedCurrencies ?? const ['SAR'];

  void _setDebit(Account? value) => setState(() {
        debit = value;
        if (!_currencies(value).contains(debitCurrency))
          debitCurrency = _currencies(value).first;
      });

  void _setCredit(Account? value) => setState(() {
        credit = value;
        if (!_currencies(value).contains(creditCurrency))
          creditCurrency = _currencies(value).first;
      });

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.type == VoucherType.receipt
            ? 'سند قبض'
            : widget.type == VoucherType.payment
                ? 'سند صرف'
                : 'قيد يومي'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: number,
                  decoration: const InputDecoration(labelText: 'رقم السند')),
              PartyPickerField(
                  label: 'بحث واختيار الطرف',
                  parties: widget.parties,
                  value: party,
                  onChanged: (value) => setState(() => party = value)),
              AccountPickerField(
                  label: 'بحث واختيار الحساب المدين',
                  accounts: widget.accounts,
                  value: debit,
                  onChanged: _setDebit),
              DropdownButtonFormField<String>(
                  initialValue: debitCurrency,
                  decoration: const InputDecoration(labelText: 'عملة المدين'),
                  items: _currencies(debit)
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => debitCurrency = value ?? debitCurrency)),
              AccountPickerField(
                  label: 'بحث واختيار الحساب الدائن',
                  accounts: widget.accounts,
                  value: credit,
                  onChanged: _setCredit),
              DropdownButtonFormField<String>(
                  initialValue: creditCurrency,
                  decoration: const InputDecoration(labelText: 'عملة الدائن'),
                  items: _currencies(credit)
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => creditCurrency = value ?? creditCurrency)),
              TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'البيان')),
              TextField(
                  controller: debitAmount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'مبلغ المدين ($debitCurrency)')),
              TextField(
                  controller: creditAmount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'مبلغ الدائن ($creditCurrency)')),
              TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'الإجمالي بالعملة الأساسية (SAR)')),
            ]))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: saving ? null : _save,
              child: const Text('حفظ وترحيل')),
        ],
      );

  Future<void> _save() async {
    final debitValue =
        double.tryParse(debitAmount.text.replaceAll(',', '')) ?? 0;
    final creditValue =
        double.tryParse(creditAmount.text.replaceAll(',', '')) ?? 0;
    final totalValue = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
    if (number.text.trim().isEmpty ||
        description.text.trim().isEmpty ||
        debitValue <= 0 ||
        creditValue <= 0 ||
        totalValue <= 0) {
      _message('أدخل بيانات السند والمبالغ الثلاثة بشكل صحيح');
      return;
    }
    if (debit?.id == null || credit?.id == null) {
      _message('اختر الحساب المدين والدائن من القائمة');
      return;
    }
    if (debit!.id == credit!.id) {
      _message('يجب اختيار حسابين مختلفين');
      return;
    }
    if (party != null &&
        party!.accountId != debit!.id &&
        party!.accountId != credit!.id) {
      _message('اختر الحساب التحليلي المرتبط بالطرف في أحد طرفي السند');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.repository.insertVoucher(Voucher(
        number: number.text.trim(),
        type: widget.type,
        description: description.text.trim(),
        amount: totalValue,
        currency: 'SAR',
        date: DateTime.now(),
        recipientName: widget.type == VoucherType.receipt ? party?.name : null,
        payerName: widget.type == VoucherType.payment ? party?.name : null,
        debitAccountId: debit!.id,
        creditAccountId: credit!.id,
        lines: [
          VoucherLine(
              accountId: debit!.id,
              partyId: party?.accountId == debit!.id ? party?.id : null,
              accountName: debit!.name,
              debit: debitValue,
              currency: debitCurrency,
              partyName: party?.name),
          VoucherLine(
              accountId: credit!.id,
              partyId: party?.accountId == credit!.id ? party?.id : null,
              accountName: credit!.name,
              credit: creditValue,
              currency: creditCurrency,
              partyName: party?.name),
        ],
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        _message(userFacingError(error,
            fallback: 'تعذر ترحيل السند. راجع الحساب والعملة والمبلغ ثم حاول مجددًا'));
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
