import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../data/accounting_authorization.dart';
import '../../../data/accounting_repository.dart';
import '../../../data/local_database.dart';
import 'account_tree.dart';

class AccountEditorDialog extends StatefulWidget {
  final AccountingRepository repository;
  final Account? account;
  final List<Account> accounts;
  const AccountEditorDialog(
      {super.key,
      required this.repository,
      this.account,
      this.accounts = const []});
  @override
  State<AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<AccountEditorDialog> {
  late final TextEditingController code;
  late final TextEditingController name;
  late final TextEditingController nameAr;
  late final TextEditingController nameEn;
  late final TextEditingController opening;
  late AccountKind kind;
  late String currency;
  final selectedCurrencies = <String>{};
  Account? parent;
  late bool isGroup;
  bool saving = false;
  bool canManage = true;
  bool checkingAccess = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    code = TextEditingController(text: account?.code ?? '');
    name = TextEditingController(text: account?.name ?? '');
    nameAr =
        TextEditingController(text: account?.nameAr ?? account?.name ?? '');
    nameEn = TextEditingController(text: account?.nameEn ?? '');
    opening = TextEditingController(text: (account?.balance ?? 0).toString());
    kind = account?.kind ?? AccountKind.asset;
    currency = account?.currency ?? 'SAR';
    selectedCurrencies.addAll(account?.supportedCurrencies ?? [currency]);
    isGroup = account?.isGroup ?? false;
    final parentId = account?.parentId;
    for (final candidate in widget.accounts) {
      if (candidate.id == parentId) {
        parent = candidate;
        break;
      }
    }
    unawaited(_checkAccess());
  }

  Future<void> _checkAccess() async {
    try {
      final db = await LocalDatabase.instance.database;
      final allowed = await AccountingAuthorization.instance
          .can(db, AccountingPermission.manageAccounts);
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
    code.dispose();
    name.dispose();
    nameAr.dispose();
    nameEn.dispose();
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(accountEditorTitle(widget.account)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!checkingAccess && !canManage)
                const Text('صلاحية تعديل دليل الحسابات غير متاحة لهذا الدور'),
              if (errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              TextField(
                  controller: code,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'رقم الحساب')),
              TextField(
                  controller: name,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'اسم الحساب')),
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
              DropdownButtonFormField<AccountKind>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'نوع الحساب'),
                  items: AccountKind.values
                      .map((item) => DropdownMenuItem(
                          value: item, child: Text(accountKindLabel(item))))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() => kind = value ?? kind)),
              DropdownButtonFormField<String>(
                  value: currency,
                  decoration: const InputDecoration(
                      labelText: 'العملة الأساسية للترحيل'),
                  items: accountCurrencies
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) =>
                          setState(() => currency = value ?? currency)),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('العملات المسموحة للحساب')),
              Wrap(spacing: 8, children: [
                for (final item in accountCurrencies)
                  FilterChip(
                    label: Text(item),
                    selected: selectedCurrencies.contains(item),
                    onSelected: saving
                        ? null
                        : (value) => setState(() => value
                            ? selectedCurrencies.add(item)
                            : selectedCurrencies.remove(item)),
                  ),
              ]),
              const SizedBox(height: 8),
              Autocomplete<Account>(
                initialValue: TextEditingValue(
                    text: parent == null ? '' : accountIdentityLabel(parent!)),
                displayStringForOption: accountIdentityLabel,
                optionsBuilder: (value) {
                  final q = value.text.toLowerCase().trim();
                  return widget.accounts.where((item) =>
                      item.id != widget.account?.id &&
                      item.active &&
                      (q.isEmpty ||
                          item.name.toLowerCase().contains(q) ||
                          item.code.contains(q)));
                },
                onSelected: (value) => setState(() => parent = value),
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                            labelText: 'الحساب الأب (اختياري)',
                            suffixIcon: Icon(Icons.account_tree_outlined)),
                        onChanged: (value) {
                          if (value.trim().isEmpty)
                            setState(() => parent = null);
                        }),
              ),
              TextField(
                  controller: opening,
                  enabled: !saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'الرصيد الافتتاحي')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('حساب تجميعي'),
                  subtitle:
                      const Text('الحساب التجميعي لا يستقبل قيودًا مباشرة'),
                  value: isGroup,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => isGroup = value)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed:
                  saving || (!checkingAccess && !canManage) ? null : _save,
              child: Text(accountSaveLabel(widget.account))),
        ],
      );

  Future<void> _save() async {
    final amount =
        double.tryParse(opening.text.replaceAll(',', '').trim()) ?? -1;
    final trimmedCode = code.text.trim();
    final trimmedName = name.text.trim();
    final trimmedNameAr = nameAr.text.trim();
    if (!RegExp(r'^\d{2,20}$').hasMatch(trimmedCode) ||
        trimmedName.length < 2 ||
        amount < 0 ||
        !amount.isFinite) {
      _message('أدخل رقم حساب رقميًا، واسمًا، ورصيدًا صحيحًا');
      return;
    }
    if (parent != null && parent!.id == widget.account?.id) {
      _message('لا يمكن جعل الحساب أبًا لنفسه');
      return;
    }
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      selectedCurrencies.add(currency);
      await widget.repository.upsertAccount(Account(
          id: widget.account?.id,
          code: trimmedCode,
          name: trimmedName,
          nameAr: trimmedNameAr.isEmpty ? trimmedName : trimmedNameAr,
          nameEn: nameEn.text.trim(),
          type: accountKindLabel(kind),
          kind: kind,
          parentId: parent?.id,
          isGroup: isGroup,
          currency: currency,
          currencies: selectedCurrencies.toList(),
          balance: amount,
          active: widget.account?.active ?? true));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        final message = error.toString();
        setState(() {
          saving = false;
          errorMessage = message.contains('رقم الحساب مستخدم مسبقًا')
              ? 'رقم الحساب مستخدم مسبقًا. اختر رقمًا آخر.'
              : 'تعذر حفظ الحساب. راجع البيانات وحاول مجددًا.';
        });
      }
    }
  }

  void _message(String text) => setState(() => errorMessage = text);
}
