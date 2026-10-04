import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../data/local_database.dart';
import '../../../../services/export_service.dart';
import '../../data/sales_engine.dart';

part 'sales_return_details_screen_part.dart';

class SalesReversalsScreen extends StatefulWidget {
  const SalesReversalsScreen({super.key});

  @override
  State<SalesReversalsScreen> createState() => _SalesReversalsScreenState();
}

class _SalesReversalsScreenState extends State<SalesReversalsScreen> {
  final engine = SalesEngine();
  List<Map<String, Object?>> invoices = [];
  bool loading = true;
  bool cancelling = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final rows = await (await LocalDatabase.instance.database)
          .query('sales_invoices', orderBy: 'issued_at DESC');
      if (mounted) setState(() { invoices = rows; loading = false; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'تعذر تحميل فواتير المرتجع والإلغاء'; });
    }
  }

  Future<void> _openInvoice(Map<String, Object?> invoice) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            SalesReturnDetailsScreen(invoice: invoice, engine: engine),
      ),
    );
    await _load();
  }

  Future<void> _cancel(Map<String, Object?> invoice) async {
    final number = invoice['number']! as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: const Text(
            'سيتم إعادة جميع الأصناف وإنشاء قيد إلغاء محاسبي. لا يمكن التراجع عن العملية تلقائيًا.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد الإلغاء')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => cancelling = true);
    try {
      final journalId = await engine.cancelSale(
        invoiceNumber: number,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الإلغاء — القيد العكسي رقم $journalId')),
      );
      await _load();
    } catch (error) {
      if (mounted) _error();
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  void _error() => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: const Text('تعذر تنفيذ العملية. تحقق من حالة الفاتورة وحاول مجددًا')),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('المرتجعات والإلغاء'),
          actions: [
            IconButton(
                onPressed: _load, icon: const Icon(Icons.refresh_rounded))
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    _header(),
                    if (error != null) Card(color: Colors.red.shade50, child: ListTile(
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text(error!),
                      trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                    )),
                    const SizedBox(height: 18),
                    if (invoices.isEmpty)
                      _emptyState()
                    else
                      ...invoices.map(_invoiceCard),
                  ],
                ),
        ),
      );

  Widget _header() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Row(children: [
          const CircleAvatar(
              backgroundColor: Color(0xFFFFEDD5),
              child: Icon(Icons.swap_horizontal_circle_outlined,
                  color: Color(0xFFC2410C))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                Text('مرتجعات دقيقة وآمنة',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                SizedBox(height: 5),
                Text(
                    'افتح الفاتورة لاختيار كمية كل صنف ومراجعة المخزون والمبلغ قبل الترحيل.',
                    style: TextStyle(color: Color(0xFF7C2D12))),
              ])),
        ]),
      );

  Widget _invoiceCard(Map<String, Object?> invoice) {
    final status = invoice['status']! as String;
    final posted = status == 'posted' || status == 'partially_returned';
    final statusColor =
        posted ? const Color(0xFF027A48) : const Color(0xFF667085);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: posted ? () => _openInvoice(invoice) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(invoice['number']! as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16))),
              _statusChip(_statusLabel(status), statusColor),
            ]),
            const SizedBox(height: 9),
            Text(
                '${invoice['customer_name']}  •  ${(invoice['total'] as num).toStringAsFixed(2)} ${invoice['currency']}'),
            const SizedBox(height: 4),
            Text(
                'تاريخ الإصدار: ${_date(DateTime.parse(invoice['issued_at']! as String))}',
                style:
                    TextStyle(color: Colors.blueGrey.shade600, fontSize: 12)),
            if (posted) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.touch_app_outlined,
                    size: 16, color: Colors.blueGrey),
                const SizedBox(width: 5),
                Text('اضغط لعرض التفاصيل واختيار الكمية',
                    style: TextStyle(
                        color: Colors.blueGrey.shade700, fontSize: 12)),
                const Spacer(),
                TextButton(
                    onPressed: () => _openInvoice(invoice),
                    child: const Text('فتح التفاصيل')),
              ]),
              Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                      onPressed: cancelling ? null : () => _cancel(invoice),
                      icon: cancelling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.block_outlined, size: 18),
                      label: Text(cancelling ? 'جارٍ الإلغاء...' : 'إلغاء الفاتورة'))),
            ] else if (invoice['reversed_at'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      'تمت المعالجة في ${_date(DateTime.parse(invoice['reversed_at']! as String))}',
                      style: TextStyle(color: statusColor, fontSize: 12))),
          ]),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      );

  Widget _emptyState() => Card(
      child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(children: const [
            Icon(Icons.receipt_long_outlined, size: 42, color: Colors.blueGrey),
            SizedBox(height: 12),
            Text('لا توجد فواتير'),
            SizedBox(height: 4),
            Text('ستظهر الفواتير المرحّلة هنا لإدارتها.',
                style: TextStyle(color: Colors.blueGrey))
          ])));

  String _statusLabel(String value) => switch (value) {
        'posted' => 'مرحّلة',
        'partially_returned' => 'مرتجع جزئي',
        'returned' => 'مرتجعة',
        'cancelled' => 'ملغاة',
        _ => value
      };
  String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}
