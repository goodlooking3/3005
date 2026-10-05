import 'package:flutter/material.dart';

import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';
import '../application/chart_of_accounts_controller.dart';
import 'account_editor_dialog.dart';
import 'account_directory_transfer_screen.dart';
import 'account_tree.dart';
import 'party_editor_dialog.dart';
import 'accounting_periods_dialog.dart';
import 'voucher_editor_dialog.dart';
import 'account_management_screens.dart';

class AccountingWorkspaceScreen extends StatefulWidget {
  final AccountingRepository repository;
  final Future<void> Function()? onOpenReports;
  final Future<void> Function()? onShowAudit;
  const AccountingWorkspaceScreen({
    super.key,
    required this.repository,
    this.onOpenReports,
    this.onShowAudit,
  });
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
        error = chart.error == null
            ? null
            : 'تعذر تحميل دليل الحسابات. اضغط تحديث وحاول مجددًا';
      });
    } catch (exception) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'تعذر تحميل البيانات المحاسبية. اضغط تحديث وحاول مجددًا';
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

  Future<void> _partyEditor([Party? party]) async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => PartyEditorDialog(
            repository: widget.repository,
            accounts: chart.allAccounts,
            party: party));
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
        LayoutBuilder(builder: (context, constraints) {
          final heading = const Text('المحاسبة والحسابات',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800));
          final refresh = IconButton(
              onPressed: _load,
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh));
          final receipt = FilledButton.icon(
              onPressed: () => _voucherEditor(VoucherType.receipt),
              icon: const Icon(Icons.add_card),
              label: const Text('سند قبض'));
          final payment = OutlinedButton.icon(
              onPressed: () => _voucherEditor(VoucherType.payment),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('سند صرف'));
          final reports = OutlinedButton.icon(
              onPressed: widget.onOpenReports,
              icon: const Icon(Icons.assessment_outlined),
              label: const Text('التقارير'));
          final audit = OutlinedButton.icon(
              onPressed: widget.onShowAudit,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('سجل التدقيق'));
          final periods = IconButton(
              onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AccountingPeriodsDialog(),
                  ).then((_) => _load()),
              tooltip: 'الفترات المالية',
              icon: const Icon(Icons.calendar_month_outlined));
          final accountManagement = OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      AccountManagementScreen(repository: widget.repository))),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('إدارة الحسابات'));
          final analyticalManagement = OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      AnalyticalAccountsScreen(repository: widget.repository))),
              icon: const Icon(Icons.people_alt_outlined),
              label: const Text('الحسابات التحليلية'));
          if (constraints.maxWidth < 1024) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [Expanded(child: heading), periods, refresh]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    receipt,
                    payment,
                    accountManagement,
                    analyticalManagement,
                    reports,
                    audit
                  ]),
                ]);
          }
          return Row(children: [
            Expanded(child: heading),
            refresh,
            periods,
            receipt,
            const SizedBox(width: 8),
            payment,
            const SizedBox(width: 8),
            reports,
            const SizedBox(width: 8),
            accountManagement,
            const SizedBox(width: 8),
            analyticalManagement,
            const SizedBox(width: 8),
            audit,
          ]);
        }),
        const SizedBox(height: 12),
        if (summary != null) _summaryStrip(),
        if (summary != null) const SizedBox(height: 12),
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
            child: Column(
              children: [
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
                    _partiesTab(),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]);

  Widget _summaryStrip() {
    final current = summary;
    if (current == null) return const SizedBox.shrink();
    Widget metric(String label, String value, String detail, IconData icon,
            Color color) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .18)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: Colors.blueGrey.shade600, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(detail,
                        style: TextStyle(
                            color: Colors.blueGrey.shade500, fontSize: 11)),
                  ]),
            ),
          ]),
        );
    final cards = <Widget>[
      metric('الرصيد النقدي', current.cashBalance.toStringAsFixed(2),
          'ريال سعودي', Icons.account_balance_wallet_outlined, Colors.blue),
      metric('الرصيد البنكي', current.bankBalance.toStringAsFixed(2),
          'ريال سعودي', Icons.account_balance_outlined, Colors.green),
      metric('القيود المسجلة', '${current.vouchersCount}', 'قيد وسند',
          Icons.receipt_long_outlined, Colors.orange),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 720) {
        return Row(children: [
          for (var index = 0; index < cards.length; index++) ...[
            Expanded(child: cards[index]),
            if (index < cards.length - 1) const SizedBox(width: 12),
          ],
        ]);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var index = 0; index < cards.length; index++) ...[
            SizedBox(width: 208, child: cards[index]),
            if (index < cards.length - 1) const SizedBox(width: 10),
          ],
        ]),
      );
    });
  }

  Widget _accountsTab() {
    final nodes = flattenAccountTree(chart.accounts, expanded: chart.expanded);
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
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
              ]))),
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${accountCountLabel(nodes.length)} • دليل هرمي',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                Text(
                    'النقدية ${summary?.cashBalance.toStringAsFixed(2) ?? '0.00'}')
              ]))),
      if (nodes.isEmpty)
        SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(accountEmptyMessage())))
      else
        SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                    (context, index) => _accountTile(nodes[index]),
                    childCount: nodes.length))),
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
                    if (mounted) {
                      final message =
                          error.toString().contains('حسابات فرعية نشطة')
                              ? 'لا يمكن إيقاف حساب له حسابات فرعية نشطة'
                              : 'تعذر تحديث حالة الحساب. حاول مجددًا';
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(message)));
                    }
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
                '${party.type == 'supplier' ? 'مورد' : 'عميل'} • ${party.phone ?? 'بدون هاتف'}\nحساب تحليلي: ${_partyAccountLabel(party)}'),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _partyEditor(party);
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    ]))),
        if (parties.isEmpty) const _Empty(text: 'لا توجد أطراف مسجلة بعد.')
      ]);

  String _partyAccountLabel(Party party) {
    for (final account in chart.allAccounts) {
      if (account.id == party.accountId) {
        return '${account.code} — ${account.name} • ${party.currency}';
      }
    }
    return 'غير مرتبط — يحتاج مراجعة';
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(24), child: Center(child: Text(text)));
}
