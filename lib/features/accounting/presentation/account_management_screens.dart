import 'package:flutter/material.dart';
import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';
import '../application/chart_of_accounts_controller.dart';
import 'account_editor_dialog.dart';
import 'account_tree.dart';
import 'party_editor_dialog.dart';

class AccountManagementScreen extends StatefulWidget {
  final AccountingRepository repository;
  const AccountManagementScreen({super.key, required this.repository});
  @override
  State<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  late final ChartOfAccountsController controller;
  @override
  void initState() { super.initState(); controller = ChartOfAccountsController(widget.repository)..load(); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  Future<void> _edit([Account? account]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => AccountEditorDialog(repository: widget.repository, account: account, accounts: controller.allAccounts));
    if (saved == true) await controller.load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة دليل الحسابات'), actions: [IconButton(onPressed: controller.load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('إضافة حساب')),
    body: AnimatedBuilder(animation: controller, builder: (_, __) {
      final nodes = flattenAccountTree(controller.accounts, expanded: controller.expanded);
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('الحسابات الرئيسية والأب والفرعية والتحليلية تُدار هنا كشجرة مستقلة.', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث برقم الحساب أو الاسم'), onChanged: controller.setQuery),
        const SizedBox(height: 12),
        if (controller.loading) const LinearProgressIndicator(),
        if (nodes.isEmpty && !controller.loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد حسابات بعد.'))),
        ...nodes.map((node) => ListTile(
          contentPadding: EdgeInsetsDirectional.only(start: node.depth * 24.0, end: 4),
          leading: CircleAvatar(child: Text(accountCodePrefix(node.account.code))),
          title: Text('${node.account.code} — ${node.account.nameAr ?? node.account.name}'),
          subtitle: Text('${node.account.nameEn?.isEmpty == false ? '${node.account.nameEn} • ' : ''}${accountKindLabel(node.account.kind)} • ${node.account.supportedCurrencies.join(', ')} • ${node.account.active ? 'نشط' : 'متوقف'}'),
          trailing: Wrap(children: [if (node.hasChildren) IconButton(onPressed: () => controller.toggleExpanded(node.account.id!), icon: Icon(controller.expanded.contains(node.account.id) ? Icons.expand_less : Icons.expand_more)), IconButton(onPressed: () => _edit(node.account), icon: const Icon(Icons.edit_outlined))]),
        )),
      ]);
    }),
  );
}

class AnalyticalAccountsScreen extends StatefulWidget {
  final AccountingRepository repository;
  const AnalyticalAccountsScreen({super.key, required this.repository});
  @override
  State<AnalyticalAccountsScreen> createState() => _AnalyticalAccountsScreenState();
}
class _AnalyticalAccountsScreenState extends State<AnalyticalAccountsScreen> {
  List<Account> accounts = const [];
  List<Party> parties = const [];
  bool loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { setState(() => loading = true); final result = await Future.wait([widget.repository.accounts(), widget.repository.parties()]); if (mounted) setState(() { accounts = result[0] as List<Account>; parties = result[1] as List<Party>; loading = false; }); }
  Future<void> _edit([Party? party]) async { final saved = await showDialog<bool>(context: context, builder: (_) => PartyEditorDialog(repository: widget.repository, accounts: accounts, party: party)); if (saved == true) await _load(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الحسابات التحليلية والعملاء والموردون'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة حساب تحليلي')),
    body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
      const Text('كل عميل أو مورد يرتبط بمعرف الحساب التحليلي الفعلي، مع العملة المسموحة والسقف الائتماني والحالة.', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      if (parties.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد حسابات تحليلية بعد.'))),
      ...parties.map((party) { final account = accounts.where((item) => item.id == party.accountId).firstOrNull; return Card(child: ListTile(leading: CircleAvatar(child: Icon(party.type == 'customer' ? Icons.person : Icons.local_shipping_outlined)), title: Text(party.nameAr ?? party.name), subtitle: Text('${party.type == 'customer' ? 'عميل' : 'مورد'} • ${account == null ? 'حساب غير موجود' : '${account.code} — ${account.name}'}\n${party.currency} • سقف ائتماني: ${party.creditLimit.toStringAsFixed(2)} • ${party.active ? 'نشط' : 'متوقف'}\n${party.phone ?? 'بدون هاتف'} • ${party.address ?? 'بدون عنوان'}'), isThreeLine: true, trailing: IconButton(onPressed: () => _edit(party), icon: const Icon(Icons.edit_outlined)))); }),
    ]),
  );
}
