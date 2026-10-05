import 'package:flutter/material.dart';

import '../../../../core/accounting.dart';
import '../../../../data/accounting_repository.dart';
import '../providers/wallet_provider.dart';
import 'wallet_account_editor_dialog.dart';
import '../widgets/transaction_filters_widget.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/wallet_card_widget.dart';
import '../../domain/models/wallet_model.dart';
import '../../domain/models/wallet_transaction.dart';

class MyWalletScreen extends StatefulWidget {
  final WalletProvider provider;
  const MyWalletScreen({super.key, required this.provider});

  @override
  State<MyWalletScreen> createState() => _MyWalletScreenState();
}

class _MyWalletScreenState extends State<MyWalletScreen> {
  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_refresh);
    widget.provider.load();
  }

  @override
  void dispose() {
    widget.provider.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.provider;
    return Scaffold(
      appBar: AppBar(
        title: const Text('محفظتي'),
        actions: [
          IconButton(
            onPressed: state.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.wallets.isEmpty ? null : _transfer,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: const Text('تحويل سريع'),
      ),
      body: state.loading && state.wallets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: state.load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (state.error != null) _error(state.error!),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        'المحافظ والحسابات',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _addWallet,
                            icon: const Icon(Icons.add_card),
                            label: const Text('إضافة محفظة'),
                          ),
                          if (state.wallets.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: () => _addAccount(state.wallets.first),
                              icon: const Icon(Icons.account_balance_outlined),
                              label: const Text('إضافة حساب'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (state.wallets.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                                'أضف محفظتك الأولى لعرض الأرصدة والحركات الموحدة.'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _addWallet,
                              icon: const Icon(Icons.add_card),
                              label: const Text('إضافة محفظة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ...state.wallets.map(
                    (wallet) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: WalletCardWidget(
                        wallet: wallet,
                        onAddAccount: () => _addAccount(wallet),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'كشف العمليات الموحد',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text('${state.transactions.length} حركة'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TransactionFiltersWidget(
                    value: state.filter,
                    onChanged: state.applyFilter,
                  ),
                  const SizedBox(height: 12),
                  ...state.transactions.map(_transactionTile),
                ],
              ),
            ),
    );
  }

  Widget _error(String message) => Card(
        color: Colors.red.shade50,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
      );

  Future<void> _addAccount(Wallet wallet) async {
    try {
      final accounts = await widget.provider.chartCatalog.repository.accounts();
      final eligible = accounts
          .where(
            (account) =>
                account.id != null &&
                !account.isGroup &&
                account.active &&
                (account.kind == AccountKind.cash ||
                    account.kind == AccountKind.bank),
          )
          .toList(growable: false);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => WalletAccountEditorDialog(
          wallet: wallet,
          accountingAccounts: eligible,
          provider: widget.provider,
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم ربط الحسابات والعملات المحددة بالمحفظة')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل الحسابات النقدية والبنكية')),
        );
      }
    }
  }

  Widget _transactionTile(WalletTransaction item) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(_icon(item.type))),
          title: Text(
            '${item.amount.toStringAsFixed(2)} ${item.currency}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${item.fromAccount} ← ${item.toAccount}\n${item.note.isEmpty ? 'بدون بيان' : item.note} • ${_statusLabel(item.status)}',
          ),
          isThreeLine: true,
          trailing: Text(item.date.toLocal().toString().split(' ').first),
        ),
      );
  IconData _icon(WalletTransactionType type) => switch (type) {
        WalletTransactionType.transfer => Icons.swap_horiz,
        WalletTransactionType.receipt => Icons.south_west,
        WalletTransactionType.purchase => Icons.shopping_bag_outlined,
        WalletTransactionType.billPayment => Icons.receipt_long_outlined,
        WalletTransactionType.topUp => Icons.add_card,
      };

  String _statusLabel(String status) => switch (status) {
        'posted' => 'مرحّلة',
        'pending' => 'معلقة',
        'confirmed' => 'مؤكدة',
        'failed' => 'فاشلة',
        'needs_reconciliation' => 'تحتاج مطابقة',
        _ => status,
      };

  Future<void> _addWallet() async {
    final name = TextEditingController();
    final provider = TextEditingController();
    final account = TextEditingController();
    var currency = 'SAR';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة محفظة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم المحفظة')),
            TextField(
                controller: provider,
                decoration: const InputDecoration(labelText: 'مزود الخدمة')),
            TextField(
                controller: account,
                decoration: const InputDecoration(
                    labelText: 'اسم الحساب داخل المحفظة')),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: const ['SAR', 'USD', 'YER']
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) => currency = value ?? 'SAR',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty ||
                  provider.text.trim().isEmpty ||
                  account.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('أكمل بيانات المحفظة والحساب')));
                return;
              }
              final walletId =
                  'wallet-${DateTime.now().microsecondsSinceEpoch}';
              await widget.provider.addWallet(
                Wallet(
                  id: walletId,
                  name: name.text.trim(),
                  provider: WalletProviderConfig(
                      id: provider.text
                          .trim()
                          .toLowerCase()
                          .replaceAll(' ', '_'),
                      name: provider.text.trim()),
                ),
                account: WalletAccount(
                    walletId: walletId,
                    name: account.text.trim(),
                    currency: currency),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ المحفظة'),
          ),
        ],
      ),
    );
    name.dispose();
    provider.dispose();
    account.dispose();
  }

  Future<void> _transfer() async => showDialog<void>(
        context: context,
        builder: (_) => TransferDialog(
          wallets: widget.provider.wallets,
          onSubmit: (from, to, amount, currency, note) =>
              widget.provider.addTransaction(
            WalletTransaction(
              fromWalletAccountId: from.id,
              toWalletAccountId: to.id,
              fromAccount: from.name,
              toAccount: to.name,
              type: WalletTransactionType.transfer,
              amount: amount,
              currency: currency,
              note: note,
              date: DateTime.now(),
            ),
          ),
        ),
      );
}
