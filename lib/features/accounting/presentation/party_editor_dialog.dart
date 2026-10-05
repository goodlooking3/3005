import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../data/accounting_authorization.dart';
import '../../../data/accounting_repository.dart';
import '../../../data/local_database.dart';
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
  late final TextEditingController nameAr;
  late final TextEditingController nameEn;
  late final TextEditingController phone;
  late final TextEditingController email;
  late final TextEditingController address;
  late final TextEditingController creditLimit;
  late String type;
  late String currency;
  Account? account;
  bool saving = false;
  bool canManage = true;
  bool checkingAccess = true;
  late bool active;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    final party = widget.party;
    name = TextEditingController(text: party?.name ?? '');
    nameAr = TextEditingController(text: party?.nameAr ?? party?.name ?? '');
    nameEn = TextEditingController(text: party?.nameEn ?? '');
    phone = TextEditingController(text: party?.phone ?? '');
    email = TextEditingController(text: party?.email ?? '');
    address = TextEditingController(text: party?.address ?? '');
    creditLimit =
        TextEditingController(text: (party?.creditLimit ?? 0).toString());
    active = party?.active ?? true;
    type = party?.type ?? 'customer';
    currency = party?.currency ?? 'SAR';
    for (final candidate in widget.accounts) {
      if (candidate.id == party?.accountId) {
        account = candidate;
        break;
      }
    }
    unawaited(_checkAccess());
  }

  Future<void> _checkAccess() async {
    try {
      final db = await LocalDatabase.instance.database;
      final allowed = await AccountingAuthorization.instance
          .can(db, AccountingPermission.manageParties);
      if (mounted) {
        setState(() {
          canManage = allowed;
          checkingAccess = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          canManage = false;
          checkingAccess = false;
        });
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    nameAr.dispose();
    nameEn.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    creditLimit.dispose();
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
        title: Text(widget.party == null
            ? 'إضافة عميل أو مورد'
            : 'تعديل العميل أو المورد'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!checkingAccess && !canManage)
                const Text('صلاحية تعديل الأطراف غير متاحة لهذا الدور'),
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
              TextField(
                  controller: nameAr,
                  enabled: !saving,
                  decoration:
                      const InputDecoration(labelText: 'الاسم بالعربي *')),
              TextField(
                  controller: nameEn,
                  enabled: !saving,
                  decoration:
                      const InputDecoration(labelText: 'الاسم بالإنجليزي')),
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
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                          currency = value ?? currency;
                          if (!analyticalAccounts.contains(account))
                            account = null;
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
                decoration:
                    const InputDecoration(labelText: 'البريد الإلكتروني'),
              ),
              TextField(
                  controller: address,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(
                  controller: creditLimit,
                  enabled: !saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'السقف الائتماني')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged:
                      saving ? null : (value) => setState(() => active = value),
                  title: const Text('تفعيل الحساب التحليلي')),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: saving || (!checkingAccess && !canManage) ? null : _save,
            child: Text(widget.party == null ? 'حفظ الطرف' : 'حفظ التعديل'),
          ),
        ],
      );

  Future<void> _save() async {
    final trimmedEmail = email.text.trim();
    final limit = double.tryParse(creditLimit.text.replaceAll(',', '').trim());
    if (name.text.trim().length < 2 ||
        nameAr.text.trim().length < 2 ||
        limit == null ||
        limit < 0 ||
        !limit.isFinite) {
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
        nameAr: nameAr.text.trim(),
        nameEn: nameEn.text.trim(),
        type: type,
        phone: phone.text.trim(),
        email: trimmedEmail,
        address: address.text.trim(),
        creditLimit: limit,
        currency: currency,
        active: active,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          errorMessage =
              'تعذر حفظ الطرف. راجع الاسم والعملة والحساب المرتبط ثم حاول مجددًا';
        });
      }
    }
  }

  void _message(String text) => setState(() => errorMessage = text);
}
