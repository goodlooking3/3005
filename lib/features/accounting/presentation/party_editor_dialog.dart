import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';
import 'account_picker_fields.dart';
import 'account_tree.dart';

class PartyEditorDialog extends StatefulWidget {
  final AccountingRepository repository;
  final List<Account> accounts;
  final Party? party;

  const PartyEditorDialog({
    super.key,
    required this.repository,
    required this.accounts,
    this.party,
  });

  @override
  State<PartyEditorDialog> createState() => _PartyEditorDialogState();
}

class _PartyEditorDialogState extends State<PartyEditorDialog> {
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController email;
  late String type;
  late String currency;
  Account? account;
  bool saving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    final party = widget.party;
    name = TextEditingController(text: party?.name ?? '');
    phone = TextEditingController(text: party?.phone ?? '');
    email = TextEditingController(text: party?.email ?? '');
    type = party?.type ?? 'customer';
    currency = party?.currency ?? 'SAR';
    for (final candidate in widget.accounts) {
      if (candidate.id == party?.accountId) {
        account = candidate;
        break;
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  List<Account> get analyticalAccounts => widget.accounts
      .where((item) =>
          item.active &&
          !item.isGroup &&
          item.kind.name == type &&
          item.supportedCurrencies.contains(currency))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.party == null ? 'إضافة عميل أو مورد' : 'تعديل العميل أو المورد'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (errorMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Text(errorMessage!),
                ),
              TextField(
                controller: name,
                enabled: !saving,
                decoration: const InputDecoration(labelText: 'الاسم *'),
              ),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'النوع *'),
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('عميل')),
                  DropdownMenuItem(value: 'supplier', child: Text('مورد')),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                        type = value ?? type;
                        account = null;
                      }),
              ),
              DropdownButtonFormField<String>(
                value: currency,
                decoration: const InputDecoration(labelText: 'عملة الطرف *'),
                items: accountCurrencies
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                        currency = value ?? currency;
                        if (!analyticalAccounts.contains(account)) account = null;
                      }),
              ),
              const SizedBox(height: 8),
              AccountPickerField(
                label: 'الحساب التحليلي المرتبط *',
                accounts: analyticalAccounts,
                value: account,
                onChanged: (value) => setState(() => account = value),
              ),
              Text(
                'يجب أن يكون الحساب نشطًا وتفصيليًا ومن نفس نوع الطرف والعملة.',
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
              ),
              TextField(
                controller: phone,
                enabled: !saving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف'),
              ),
              TextField(
                controller: email,
                enabled: !saving,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(widget.party == null ? 'حفظ الطرف' : 'حفظ التعديل'),
          ),
        ],
      );

  Future<void> _save() async {
    final trimmedEmail = email.text.trim();
    if (name.text.trim().length < 2) {
      _message('أدخل اسم الطرف بشكل صحيح');
      return;
    }
    if (account == null) {
      _message('اختر الحساب التحليلي المرتبط بالطرف');
      return;
    }
    if (trimmedEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmedEmail)) {
      _message('أدخل بريدًا إلكترونيًا صحيحًا أو اترك الحقل فارغًا');
      return;
    }
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      await widget.repository.upsertParty(Party(
        id: widget.party?.id,
        accountId: account!.id,
        name: name.text.trim(),
        type: type,
        phone: phone.text.trim(),
        email: trimmedEmail,
        currency: currency,
        active: widget.party?.active ?? true,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          errorMessage = 'تعذر حفظ الطرف. راجع الاسم والعملة والحساب المرتبط ثم حاول مجددًا';
        });
      }
    }
  }

  void _message(String text) => setState(() => errorMessage = text);
}
