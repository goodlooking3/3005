import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../core/user_facing_errors.dart';
import '../../../data/accounting_authorization.dart';
import '../../../data/accounting_repository.dart';
import '../../../data/local_database.dart';
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
  DateTime? dueDate;
  String debitCurrency = 'SAR';
  String creditCurrency = 'SAR';
  bool saving = false;
  bool checkingAccess = true;
  bool canPost = false;
  bool numberEdited = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPostingAccessAndNumber());
    if (widget.accounts.length > 1) {
      debit = widget.accounts.first;
      credit = widget.accounts[1];
      debitCurrency = debit!.supportedCurrencies.first;
      creditCurrency = credit!.supportedCurrencies.first;
    }
    if (widget.parties.isNotEmpty) party = widget.parties.first;
  }

  Future<void> _loadPostingAccessAndNumber() async {
    try {
      final db = await LocalDatabase.instance.database;
      final allowed = await AccountingAuthorization.instance
          .can(db, AccountingPermission.postVouchers);
      final generated = allowed
          ? await widget.repository.nextVoucherNumber(widget.type)
          : null;
      if (!mounted) return;
      setState(() {
        canPost = allowed;
        checkingAccess = false;
        if (generated != null && !numberEdited) number.text = generated;
      });
    } catch (_) {
      if (mounted) setState(() => checkingAccess = false);
    }
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

  bool get _supportsDueDate =>
      debit?.kind == AccountKind.customer ||
      credit?.kind == AccountKind.supplier;

  Future<void> _pickDueDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: dueDate ?? DateTime.now(),
    );
    if (selected != null) setState(() => dueDate = selected);
  }

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
                  onChanged: (_) => numberEdited = true,
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
              if (_supportsDueDate)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDueDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(dueDate == null
                          ? 'تاريخ الاستحقاق (اختياري)'
                          : 'الاستحقاق: ${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}'),
                    ),
                  ),
                  if (dueDate != null)
                    IconButton(
                      tooltip: 'مسح تاريخ الاستحقاق',
                      onPressed: () => setState(() => dueDate = null),
                      icon: const Icon(Icons.close),
                    ),
                ]),
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
              if (!checkingAccess && !canPost)
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('لا تملك صلاحية ترحيل القيود'),
                ),
            ]))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: saving || checkingAccess || !canPost ? null : _save,
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
    if (dueDate != null) {
      final receivable = debit!.kind == AccountKind.customer &&
          party?.type == 'customer' &&
          party?.accountId == debit!.id &&
          debitValue > 0;
      final payable = credit!.kind == AccountKind.supplier &&
          party?.type == 'supplier' &&
          party?.accountId == credit!.id &&
          creditValue > 0;
      if (!receivable && !payable) {
        _message('يرتبط تاريخ الاستحقاق بذمم عميل أو مورد مع طرف مطابق');
        return;
      }
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
        dueDate: dueDate,
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
            fallback:
                'تعذر ترحيل السند. راجع الحساب والعملة والمبلغ ثم حاول مجددًا'));
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
