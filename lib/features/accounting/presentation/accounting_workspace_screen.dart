import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';
import '../application/chart_of_accounts_controller.dart';
import 'account_editor_dialog.dart';
import 'account_directory_transfer_screen.dart';
import 'account_tree.dart';
import 'party_editor_dialog.dart';
import 'voucher_editor_dialog.dart';

class AccountingWorkspaceScreen extends StatefulWidget {
  final AccountingRepository repository;
  const AccountingWorkspaceScreen({super.key, required this.repository});
  @override
  State<AccountingWorkspaceScreen> createState() =>
      _AccountingWorkspaceScreenState();
}

class _AccountingWorkspaceScreenState extends State<AccountingWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ChartOfAccountsController chart;
  List<Voucher> vouchers = const [];
  List<Party> parties = const [];
  FinancialSummary? summary;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    chart = ChartOfAccountsController(widget.repository)..addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    chart.removeListener(_refresh);
    chart.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    await chart.load();
    try {
      final result = await Future.wait<Object>([
        widget.repository.vouchers(),
        widget.repository.parties(),
        widget.repository.summary()
      ]);
      if (!mounted) return;
      setState(() {
        vouchers = result[0] as List<Voucher>;
        parties = result[1] as List<Party>;
        summary = result[2] as FinancialSummary;
        loading = false;
        error = chart.error?.toString();
      });
    } catch (exception) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'تعذر تحميل البيانات المحاسبية: $exception';
        });
    }
  }

  Future<void> _accountEditor([Account? account]) async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => AccountEditorDialog(
            repository: widget.repository,
            account: account,
            accounts: chart.allAccounts));
    if (saved == true) await _load();
  }

  Future<void> _directoryTransfer() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AccountDirectoryTransferScreen(repository: widget.repository)));
    await _load();
  }

  Future<void> _partyEditor() async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => PartyEditorDialog(repository: widget.repository));
    if (saved == true) await _load();
  }

  Future<void> _voucherEditor(VoucherType type) async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => VoucherEditorDialog(
            repository: widget.repository,
            type: type,
            accounts:
                chart.allAccounts.where((a) => a.active && !a.isGroup).toList(),
            parties: parties));
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
              child: Text('المحاسبة والحسابات',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          IconButton(
              onPressed: _load,
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh)),
          FilledButton.icon(
              onPressed: () => _voucherEditor(VoucherType.receipt),
              icon: const Icon(Icons.add_card),
              label: const Text('سند قبض')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
              onPressed: () => _voucherEditor(VoucherType.payment),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('سند صرف'))
        ]),
        const SizedBox(height: 12),
        if (error != null)
          Card(
              color: Colors.red.shade50,
              child: Padding(
                  padding: const EdgeInsets.all(12), child: Text(error!))),
        if (loading) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Expanded(
            child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  TabBar(controller: _tabs, tabs: const [
                    Tab(
                        icon: Icon(Icons.account_tree_outlined),
                        text: 'دليل الحسابات'),
                    Tab(
                        icon: Icon(Icons.receipt_long_outlined),
                        text: 'السندات والقيود'),
                    Tab(icon: Icon(Icons.people_alt_outlined), text: 'الأطراف')
                  ]),
                  Expanded(
                      child: TabBarView(controller: _tabs, children: [
                    _accountsTab(),
                    _vouchersTab(),
                    _partiesTab()
                  ]))
                ]))),
      ]);

  Widget _accountsTab() {
    final nodes = flattenAccountTree(chart.accounts, expanded: chart.expanded);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
                width: 260,
                child: TextField(
                    decoration: InputDecoration(
                        hintText: accountSearchHint(),
                        prefixIcon: const Icon(Icons.search)),
                    onChanged: chart.setQuery)),
            DropdownButton<AccountKind?>(
                value: chart.kind,
                hint: const Text('كل الأنواع'),
                items: [
                  const DropdownMenuItem<AccountKind?>(
                      value: null, child: Text('كل الأنواع')),
                  ...AccountKind.values.map((kind) => DropdownMenuItem(
                      value: kind, child: Text(accountKindLabel(kind))))
                ],
                onChanged: chart.setKind),
            FilterChip(
                label: const Text('إظهار المتوقفة'),
                selected: chart.includeInactive,
                onSelected: chart.setIncludeInactive),
            OutlinedButton.icon(
                onPressed: () => _accountEditor(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة حساب')),
            OutlinedButton.icon(
                onPressed: _directoryTransfer,
                icon: const Icon(Icons.import_export),
                label: const Text('استيراد / تصدير XLSX')),
          ])),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Expanded(
                child: Text('${accountCountLabel(nodes.length)} • دليل هرمي',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            Text('النقدية ${summary?.cashBalance.toStringAsFixed(2) ?? '0.00'}')
          ])),
      Expanded(
          child: nodes.isEmpty
              ? Center(child: Text(accountEmptyMessage()))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: nodes.length,
                  itemBuilder: (context, index) => _accountTile(nodes[index]))),
    ]);
  }

  Widget _accountTile(AccountTreeNode node) {
    final account = node.account;
    return ListTile(
        contentPadding:
            EdgeInsetsDirectional.only(start: 12 + node.depth * 26.0, end: 8),
        leading: CircleAvatar(child: Text(accountCodePrefix(account.code))),
        title: Text(accountIdentityLabel(account),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${accountKindLabel(account.kind)} • ${accountGroupLabel(account)} • ${account.currency} • ${accountStatusLabel(account)}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(accountBalanceLabel(account)),
          if (node.hasChildren)
            IconButton(
                icon: Icon(chart.expanded.contains(account.id)
                    ? Icons.expand_less
                    : Icons.expand_more),
                tooltip: 'فتح أو طي الحسابات الفرعية',
                onPressed: () => chart.toggleExpanded(account.id!)),
          PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') await _accountEditor(account);
                if (value == 'status') {
                  try {
                    await chart.setActive(account, !account.active);
                  } catch (error) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('تعذر تحديث حالة الحساب: $error')));
                  }
                }
              },
              itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(
                        value: 'status',
                        child: Text(
                            account.active ? 'إيقاف الحساب' : 'تفعيل الحساب'))
                  ])
        ]),
        isThreeLine: true);
  }

  String _voucherLinesLabel(Voucher voucher) => voucher.lines.isEmpty
      ? 'تفاصيل السند غير متاحة'
      : voucher.lines.map((line) {
          final side = line.debit > 0 ? 'مدين' : 'دائن';
          final value = line.debit > 0 ? line.debit : line.credit;
          return '$side ${value.toStringAsFixed(2)} ${line.currency ?? voucher.currency}';
        }).join(' • ');

  Widget _vouchersTab() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Expanded(
              child: Text('السندات والقيود المرحّلة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          OutlinedButton.icon(
              onPressed: () => _voucherEditor(VoucherType.journal),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('قيد يومي'))
        ]),
        ...vouchers.map((voucher) => Card(
            child: ListTile(
                leading: Icon(voucher.type == VoucherType.receipt
                    ? Icons.south_west
                    : Icons.north_east),
                title: Text(voucher.number,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${voucher.description}\n${voucher.date.toLocal()}\n${_voucherLinesLabel(voucher)}'),
                isThreeLine: true,
                trailing: Text(
                    '${voucher.amount.toStringAsFixed(2)} ${voucher.currency}')))),
        if (vouchers.isEmpty) const _Empty(text: 'لا توجد سندات مرحّلة بعد.')
      ]);
  Widget _partiesTab() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Expanded(
              child: Text('دليل العملاء والموردين',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          OutlinedButton.icon(
              onPressed: _partyEditor,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('إضافة طرف'))
        ]),
        ...parties.map((party) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(party.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${party.type == 'supplier' ? 'مورد' : 'عميل'} • ${party.phone ?? 'بدون هاتف'}'),
            trailing: Text(party.currency))),
        if (parties.isEmpty) const _Empty(text: 'لا توجد أطراف مسجلة بعد.')
      ]);
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(24), child: Center(child: Text(text)));
}
