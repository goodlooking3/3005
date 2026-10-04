import 'package:flutter/material.dart';

import '../../../../core/accounting.dart';
import '../providers/wallet_provider.dart';
import '../../domain/models/wallet_model.dart';

class WalletAccountEditorDialog extends StatefulWidget {
  final Wallet wallet;
  final List<Account> accountingAccounts;
  final WalletProvider provider;

  const WalletAccountEditorDialog({
    super.key,
    required this.wallet,
    required this.accountingAccounts,
    required this.provider,
  });

  @override
  State<WalletAccountEditorDialog> createState() =>
      _WalletAccountEditorDialogState();
}

class _WalletAccountEditorDialogState extends State<WalletAccountEditorDialog> {
  late final TextEditingController _nameController;
  Account? _selectedAccount;
  Set<String> _selectedCurrencies = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedAccount =
        widget.accountingAccounts.isEmpty ? null : widget.accountingAccounts.first;
    _nameController = TextEditingController(text: _selectedAccount?.name ?? '');
    _resetCurrencies();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Set<String> _availableCurrencies(Account account) {
    final alreadyLinked = widget.wallet.accounts
        .where((item) => item.accountId == account.id)
        .map((item) => item.currency.toUpperCase())
        .toSet();
    return account.supportedCurrencies
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty && !alreadyLinked.contains(value))
        .toSet();
  }

  void _resetCurrencies() {
    final account = _selectedAccount;
    _selectedCurrencies = account == null ? {} : _availableCurrencies(account);
  }

  Future<void> _save() async {
    final account = _selectedAccount;
    final name = _nameController.text.trim();
    if (account?.id == null || name.isEmpty || _selectedCurrencies.isEmpty) {
      setState(() => _error = 'اختر حسابًا محاسبيًا واسمًا وعملة واحدة على الأقل.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final walletAccounts = _selectedCurrencies
        .map(
          (currency) => WalletAccount(
            walletId: widget.wallet.id,
            name: name,
            currency: currency,
            accountId: account!.id,
            accountingCode: account.code,
            accountingName: account.name,
          ),
        )
        .toList(growable: false);
    final saved = await widget.provider.addAccounts(walletAccounts);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.provider.error ?? 'تعذر حفظ الحساب. راجع العملة والربط ثم أعد المحاولة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _selectedAccount == null
        ? const <String>{}
        : _availableCurrencies(_selectedAccount!);
    return AlertDialog(
      title: Text('إضافة حساب إلى ${widget.wallet.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selectedAccount?.id,
                decoration: const InputDecoration(
                  labelText: 'الحساب النقدي أو البنكي المرتبط',
                  border: OutlineInputBorder(),
                ),
                items: widget.accountingAccounts
                    .where((account) => account.id != null)
                    .map(
                      (account) => DropdownMenuItem<int>(
                        value: account.id,
                        child: Text('${account.code} — ${account.name}'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (id) {
                        final account = widget.accountingAccounts
                            .where((item) => item.id == id)
                            .firstOrNull;
                        setState(() {
                          _selectedAccount = account;
                          _nameController.text = account?.name ?? '';
                          _resetCurrencies();
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'اسم الحساب داخل المحفظة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'العملات المسموحة لهذا الحساب (يمكن اختيار أكثر من عملة)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (widget.accountingAccounts.isEmpty)
                const Text('لا توجد حسابات نقدية أو بنكية تفصيلية نشطة لإضافتها.'),
              if (currencies.isEmpty && _selectedAccount != null)
                const Text('لا توجد عملات متاحة جديدة لهذا الحساب؛ تحقق من دليل الحسابات.'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: currencies
                    .map(
                      (currency) => FilterChip(
                        label: Text(currency),
                        selected: _selectedCurrencies.contains(currency),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(() {
                                  if (selected) {
                                    _selectedCurrencies.add(currency);
                                  } else {
                                    _selectedCurrencies.remove(currency);
                                  }
                                }),
                      ),
                    )
                    .toList(growable: false),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving || _selectedCurrencies.isEmpty ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded),
          label: Text(_saving ? 'جارٍ الربط...' : 'حفظ الربط'),
        ),
      ],
    );
  }
}
