import 'package:flutter/material.dart';

import '../application/accounting_reports_controller.dart';
import '../domain/journal_entry.dart';
import '../../../data/accounting_repository.dart';
import '../../../services/report_service.dart';

class AccountingReportsScreen extends StatefulWidget {
  final AccountingReportsController controller;
  const AccountingReportsScreen({super.key, required this.controller});

  @override
  State<AccountingReportsScreen> createState() =>
      _AccountingReportsScreenState();
}

class _AccountingReportsScreenState extends State<AccountingReportsScreen> {
  int section = 0;
  String query = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => mounted ? setState(() {}) : null;

  String _date(DateTime value) {
    final display = value.hour == 23 && value.minute == 59
        ? value.subtract(const Duration(days: 1))
        : value;
    return '${display.year}-${display.month.toString().padLeft(2, '0')}-${display.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate(
      AccountingReportsController controller, bool start) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: start
          ? controller.from ?? DateTime.now()
          : controller.to ?? DateTime.now(),
    );
    if (selected == null) return;
    final end = selected
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    await controller.setDateRange(
        start ? selected : controller.from, start ? controller.to : end);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير المحاسبية'),
        actions: [
          IconButton(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.menu_book_outlined),
                      label: Text('اليومية العامة')),
                  ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.account_balance_outlined),
                      label: Text('ميزان المراجعة')),
                  ButtonSegment(
                      value: 2,
                      icon: Icon(Icons.trending_up_outlined),
                      label: Text('الأرباح والخسائر')),
                  ButtonSegment(
                      value: 3,
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('المركز المالي')),
                  ButtonSegment(
                      value: 4,
                      icon: Icon(Icons.person_search_outlined),
                      label: Text('أعمار العملاء')),
                  ButtonSegment(
                      value: 5,
                      icon: Icon(Icons.local_shipping_outlined),
                      label: Text('أعمار الموردين')),
                  ButtonSegment(
                      value: 6,
                      icon: Icon(Icons.fact_check_outlined),
                      label: Text('سجل التدقيق')),
                ],
                selected: {section},
                onSelectionChanged: (value) =>
                    setState(() => section = value.first),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<String?>(
                  value: controller.currency,
                  hint: const Text('كل العملات'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('كل العملات')),
                    ...controller.currencies.map((item) =>
                        DropdownMenuItem<String?>(
                            value: item.code,
                            child: Text('${item.code} — ${item.name}'))),
                  ],
                  onChanged: controller.setCurrency,
                ),
                OutlinedButton.icon(
                    onPressed: () => _pickDate(controller, true),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(controller.from == null
                        ? 'من تاريخ'
                        : _date(controller.from!))),
                OutlinedButton.icon(
                    onPressed: () => _pickDate(controller, false),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(controller.to == null
                        ? 'إلى تاريخ'
                        : _date(controller.to!))),
                if (controller.currency != null ||
                    controller.from != null ||
                    controller.to != null)
                  TextButton(
                      onPressed: () async {
                        await controller.setDateRange(null, null);
                        await controller.setCurrency(null);
                      },
                      child: const Text('مسح الفلاتر')),
              ],
            ),
            const SizedBox(height: 8),
            if (section == 0)
              TextField(
                onChanged: (value) {
                  query = value;
                  controller.load(query: value);
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ابحث برقم القيد أو البيان',
                ),
              ),
            const SizedBox(height: 12),
            if (controller.loading) const LinearProgressIndicator(),
            if (controller.error != null)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(controller.error!)),
            Expanded(child: _body(controller)),
          ],
        ),
      ),
    );
  }

  Widget _body(AccountingReportsController controller) => switch (section) {
        0 => _journal(controller.journal),
        1 => _trialBalance(controller.trialBalance),
        2 => _profitLoss(controller.profitLoss),
        3 => _balanceSheet(controller.balanceSheet),
        4 => _aging(controller.receivablesAging, 'customer', controller),
        5 => _aging(controller.payablesAging, 'supplier', controller),
        _ => _audit(controller.audit),
      };

  Widget _journal(List<JournalEntry> entries) => entries.isEmpty
      ? const Center(child: Text('لا توجد قيود في اليومية العامة بعد.'))
      : ListView(children: entries.map(_journalTile).toList());

  Widget _journalTile(JournalEntry entry) => Card(
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: entry.balanced
                ? const Color(0xFFE8F8F0)
                : const Color(0xFFFFE8E8),
            child: Icon(entry.balanced
                ? Icons.check_rounded
                : Icons.warning_amber_rounded),
          ),
          title: Text(entry.number,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${entry.description}\n${entry.date.toLocal()}'),
          children: [
            ListTile(
                title: const Text('إجمالي المدين'),
                trailing: Text(entry.debitTotal.toStringAsFixed(2))),
            ListTile(
                title: const Text('إجمالي الدائن'),
                trailing: Text(entry.creditTotal.toStringAsFixed(2))),
            ListTile(
                title: const Text('الحالة'),
                trailing: Text(entry.balanced ? 'متوازن' : 'غير متوازن')),
          ],
        ),
      );

  Widget _trialBalance(List<TrialBalanceRow> rows) {
    final debit = rows.fold<double>(0, (sum, row) => sum + row.debit);
    final credit = rows.fold<double>(0, (sum, row) => sum + row.credit);
    return ListView(
      children: [
        Card(
            child: ListTile(
                title: const Text('إجمالي المدين'),
                trailing: Text(debit.toStringAsFixed(2)))),
        Card(
            child: ListTile(
                title: const Text('إجمالي الدائن'),
                trailing: Text(credit.toStringAsFixed(2)))),
        ...rows.map((row) => ListTile(
              leading: Text(row.code),
              title: Text(row.account),
              trailing: Text(
                  'مدين ${row.debit.toStringAsFixed(2)} • دائن ${row.credit.toStringAsFixed(2)}'),
            )),
        if (rows.isEmpty)
          const Center(child: Text('لا توجد بيانات لميزان المراجعة بعد.')),
      ],
    );
  }

  Widget _profitLoss(ProfitLossReport? report) {
    if (report == null) {
      return const Center(child: Text('لا توجد بيانات الأرباح والخسائر بعد.'));
    }
    return ListView(
      children: [
        Card(
            child: ListTile(
                title: const Text('الإيرادات'),
                trailing: Text(report.revenue.toStringAsFixed(2)))),
        Card(
            child: ListTile(
                title: const Text('المصروفات'),
                trailing: Text(report.expenses.toStringAsFixed(2)))),
        Card(
          color: report.net >= 0
              ? const Color(0xFFE8F8F0)
              : const Color(0xFFFFE8E8),
          child: ListTile(
              title: const Text('صافي النتيجة'),
              trailing: Text(report.net.toStringAsFixed(2))),
        ),
      ],
    );
  }

  Widget _balanceSheet(BalanceSheetReport? report) {
    if (report == null) {
      return const Center(child: Text('لا توجد بيانات للمركز المالي.'));
    }
    return ListView(
      children: [
        ListTile(
          title: const Text('كما في'),
          trailing: Text('${_date(report.asOf)} · ${report.currency}'),
        ),
        _positionSection('الأصول', report.assetsLines, report.assets),
        _positionSection(
            'الالتزامات', report.liabilitiesLines, report.liabilities),
        _positionSection('حقوق الملكية', report.equityLines, report.equity),
        Card(
          child: ListTile(
            title: const Text('نتيجة غير مقفلة حتى التاريخ'),
            subtitle:
                const Text('صافي الإيرادات والمصروفات من بداية بيانات الدفتر.'),
            trailing: Text(report.unclosedResult.toStringAsFixed(2)),
          ),
        ),
        Card(
          color: report.isBalanced
              ? const Color(0xFFE8F8F0)
              : const Color(0xFFFFE8E8),
          child: ListTile(
            title: const Text('الالتزامات وحقوق الملكية والنتيجة'),
            subtitle:
                Text('فرق التوازن: ${report.difference.toStringAsFixed(2)}'),
            trailing: Text(report.liabilitiesAndEquity.toStringAsFixed(2)),
          ),
        ),
      ],
    );
  }

  Widget _positionSection(
          String title, List<FinancialPositionLine> rows, double total) =>
      Card(
        child: ExpansionTile(
          title: Text(title),
          subtitle: Text('الإجمالي ${total.toStringAsFixed(2)}'),
          children: rows.isEmpty
              ? const [ListTile(title: Text('لا توجد أرصدة.'))]
              : rows
                  .map((row) => ListTile(
                        title: Text(row.account),
                        subtitle: Text(row.code),
                        trailing: Text(row.balance.toStringAsFixed(2)),
                      ))
                  .toList(),
        ),
      );

  Widget _aging(
    PartyAgingReport? report,
    String partyType,
    AccountingReportsController controller,
  ) {
    if (report == null) {
      return const Center(child: Text('لا توجد بيانات للأعمار.'));
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
              'تُحسب الأعمار من تاريخ الاستحقاق اليدوي عند إدخاله، وإلا من تاريخ القيد. الأرصدة بلا تاريخ تعاقدي لا تعني أنها متأخرة؛ وتُعرض العملات منفصلة.'),
        ),
        if (report.rows.isEmpty)
          const ListTile(
              title:
                  Text('لا توجد حركات ذمم منسوبة لأطراف حتى التاريخ المحدد.')),
        ...report.rows.map((row) => Card(
              child: InkWell(
                onTap: () async {
                  final lines = await controller.loadPartyStatement(
                    partyId: row.partyId,
                    partyType: partyType,
                  );
                  if (mounted) _showPartyStatement(row.partyName, lines);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(row.partyName),
                        subtitle: Text('صافي الذمة · ${row.currency}'),
                        trailing: Text(row.netBalance.toStringAsFixed(2)),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _ageChip('غير مستحق', row.notDue),
                          _ageChip('0–30', row.days0To30),
                          _ageChip('31–60', row.days31To60),
                          _ageChip('61–90', row.days61To90),
                          _ageChip('أكثر من 90', row.daysOver90),
                          _ageChip('رصيد دائن/دفعة', row.unappliedCredit),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )),
        ...report.unallocated.map((row) => Card(
              color: const Color(0xFFFFF4D6),
              child: ListTile(
                title: const Text('رصيد غير موزع على الأطراف'),
                subtitle:
                    Text('افتتاحي أو حركة بلا رابط طرف · ${row.currency}'),
                trailing: Text(row.balance.toStringAsFixed(2)),
              ),
            )),
      ],
    );
  }

  Widget _ageChip(String label, double amount) => Chip(
        label: Text('$label: ${amount.toStringAsFixed(2)}'),
        visualDensity: VisualDensity.compact,
      );

  Future<void> _showPartyStatement(
    String partyName,
    List<PartyStatementLine> lines,
  ) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('كشف الذمة — $partyName',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const Text(
                    'الرصيد الافتتاحي غير المنسوب لتفصيل طرف لا يظهر ضمن الحركات أدناه.'),
                Expanded(
                  child: lines.isEmpty
                      ? const Center(
                          child: Text('لا توجد حركات ذمم لهذا الطرف.'))
                      : ListView.builder(
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            return ListTile(
                              title:
                                  Text('${line.number} · ${_date(line.date)}'),
                              subtitle: Text(
                                  '${line.description}\nمدين ${line.debit.toStringAsFixed(2)} • دائن ${line.credit.toStringAsFixed(2)}'),
                              trailing: SizedBox(
                                width: 76,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(line.currency),
                                    Text(line.balance.toStringAsFixed(2)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _audit(List<AuditRecord> records) => records.isEmpty
      ? const Center(child: Text('لا توجد عمليات مسجلة بعد.'))
      : ListView(
          children: records
              .map((record) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(record.action,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${record.details}\n${record.createdAt.toLocal()}'),
                    ),
                  ))
              .toList(),
        );
}
