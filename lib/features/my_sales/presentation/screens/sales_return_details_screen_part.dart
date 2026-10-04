part of 'sales_reversals_screen.dart';

class SalesReturnDetailsScreen extends StatefulWidget {
  final Map<String, Object?> invoice;
  final SalesEngine engine;

  const SalesReturnDetailsScreen(
      {super.key, required this.invoice, required this.engine});

  @override
  State<SalesReturnDetailsScreen> createState() =>
      _SalesReturnDetailsScreenState();
}

class _SalesReturnDetailsScreenState extends State<SalesReturnDetailsScreen> {
  List<Map<String, Object?>> lines = [];
  final quantities = <int, double>{};
  final controllers = <int, TextEditingController>{};
  bool loading = true;
  bool submitting = false;
  String? error;

  String get number => widget.invoice['number']! as String;

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  @override
  void dispose() {
    for (final controller in controllers.values) controller.dispose();
    super.dispose();
  }

  Future<void> _loadLines() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final db = await LocalDatabase.instance.database;
      final loaded = await db.rawQuery('''
      SELECT sil.id, sil.item_name, sil.quantity sold_quantity, sil.unit_price,
        sil.unit_cost, ii.quantity current_stock,
        COALESCE((SELECT SUM(srl.quantity) FROM sales_return_lines srl WHERE srl.invoice_line_id = sil.id), 0) returned_quantity
      FROM sales_invoice_lines sil
      JOIN inventory_items ii ON ii.id = sil.item_id
      WHERE sil.invoice_number = ? ORDER BY sil.id ASC
    ''', [number]);
      debugPrint('sales return detail debug: invoice=$number rows=${loaded.length}');
      for (final line in loaded) {
        final id = line['id']! as int;
        controllers[id] = TextEditingController(text: '0');
        quantities[id] = 0;
      }
      if (mounted)
        setState(() {
          lines = loaded;
          loading = false;
          error = null;
        });
    } catch (exception) {
      debugPrint('sales return detail debug: $exception');
      if (mounted)
        setState(() {
          loading = false;
          error = 'تعذر تحميل أصناف الفاتورة. اضغط تحديث وحاول مجددًا';
        });
    }
  }

  double _num(Object? value) => (value as num? ?? 0).toDouble();
  double _remaining(Map<String, Object?> line) =>
      _num(line['sold_quantity']) - _num(line['returned_quantity']);

  void _setQuantity(int id, double value) {
    final line = lines.firstWhere((row) => row['id'] == id);
    final max = _remaining(line);
    final safe = value.clamp(0, max).toDouble();
    quantities[id] = safe;
    controllers[id]?.text = safe == 0 ? '' : _format(safe);
    setState(() {});
  }

  void _fillAll() {
    for (final line in lines)
      _setQuantity(line['id']! as int, _remaining(line));
  }

  double get returnTotal => lines.fold(
      0,
      (sum, line) =>
          sum +
          (quantities[line['id']! as int] ?? 0) * _num(line['unit_price']));
  double get returnCost => lines.fold(
      0,
      (sum, line) =>
          sum +
          (quantities[line['id']! as int] ?? 0) * _num(line['unit_cost']));
  double get returnQuantity =>
      quantities.values.fold(0, (sum, value) => sum + value);

  Future<void> _submitReturn() async {
    final selected = <int, double>{
      for (final entry in quantities.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (selected.isEmpty) {
      _message('حدد كمية مرتجع واحدة على الأقل', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المرتجع الجزئي'),
        content: Text(
            'سيتم إرجاع ${_format(returnQuantity)} وحدة بقيمة ${_format(returnTotal)} ${widget.invoice['currency']}. سيتم إنشاء قيد عكسي وتحديث المخزون.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('مراجعة')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ترحيل المرتجع')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => submitting = true);
    late final int journal;
    try {
      journal = await widget.engine.returnSale(
        invoiceNumber: number,
        quantitiesByLineId: selected,
      );
    } catch (_) {
      if (mounted) {
        setState(() => submitting = false);
        _message(
            'تعذر ترحيل المرتجع. تحقق من الكمية وحالة الفاتورة ثم حاول مجددًا',
            error: true);
      }
      return;
    }
    if (!mounted) return;

    final creditNoteLines = <CreditNoteLine>[];
    for (final line in lines) {
      final quantity = selected[line['id']! as int] ?? 0;
      if (quantity <= 0) continue;
      final unitPrice = _num(line['unit_price']);
      creditNoteLines.add(CreditNoteLine(
        itemName: line['item_name']! as String,
        quantity: quantity,
        unitPrice: unitPrice,
        total: quantity * unitPrice,
      ));
    }

    late final Uint8List pdf;
    try {
      pdf = await ExportService.buildCreditNotePdf(
        invoiceNumber: number,
        customerName: widget.invoice['customer_name']! as String,
        currency: widget.invoice['currency']! as String,
        date: DateTime.now(),
        journalId: journal,
        total: returnTotal,
        lines: creditNoteLines,
      );
    } catch (_) {
      if (mounted) {
        _message('تم ترحيل المرتجع — القيد $journal — لكن تعذر إنشاء ملف إشعار الدائن.');
        Navigator.pop(context);
      }
      return;
    }
    if (!mounted) return;

    var printOptionsOpened = false;
    try {
      await Printing.layoutPdf(
        name: 'إشعار دائن CN-$number-$journal.pdf',
        onLayout: (_) async => pdf,
      );
      printOptionsOpened = true;
    } catch (_) {
      // The return is already committed; offer the generated PDF through sharing.
    }
    if (!mounted) return;
    _message(printOptionsOpened
        ? 'تم ترحيل المرتجع وتجهيز إشعار الدائن وفتح خيارات الطباعة — القيد $journal.'
        : 'تم ترحيل المرتجع — القيد $journal — وتعذر فتح الطباعة؛ يمكنك محاولة المشاركة.');
    await _offerSharing(pdf, journal);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _offerSharing(Uint8List pdf, int journalId) async {
    if (!mounted) return;
    final channel = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('إرسال إشعار الدائن للعميل',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'سيتم فتح قائمة المشاركة مع إرفاق ملف PDF. اختر البريد أو واتساب ثم راجع المستلم وأرسل يدويًا.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 16),
            ListTile(
                leading: const CircleAvatar(child: Icon(Icons.email_outlined)),
                title: const Text('البريد الإلكتروني'),
                subtitle: const Text('إرفاق إشعار الدائن برسالة بريد'),
                onTap: () => Navigator.pop(context, 'email')),
            ListTile(
                leading: const CircleAvatar(child: Icon(Icons.chat_outlined)),
                title: const Text('واتساب'),
                subtitle: const Text('إرفاق إشعار الدائن برسالة واتساب'),
                onTap: () => Navigator.pop(context, 'whatsapp')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('لاحقًا')),
          ]),
        ),
      ),
    );
    if (channel == null || !mounted) return;
    try {
      await Printing.sharePdf(
          bytes: pdf, filename: 'إشعار-دائن-$number-$journalId.pdf');
      if (mounted)
        _message('تم فتح قائمة المشاركة. اختر التطبيق المقصود وراجع المستلم قبل الإرسال.');
    } catch (_) {
      if (mounted)
        _message('تم ترحيل المرتجع، لكن تعذر فتح خيارات مشاركة إشعار الدائن.',
            error: true);
    }
  }

  void _message(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
          content: Text(text)));
  String _format(double value) =>
      value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('تفاصيل $number')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                  onPressed: _loadLines,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة المحاولة')),
                            ])))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                    _invoiceSummary(),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(
                          child: Text('أصناف الفاتورة',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800))),
                      TextButton.icon(
                          onPressed: _fillAll,
                          icon: const Icon(Icons.done_all_rounded),
                          label: const Text('إرجاع الكل'))
                    ]),
                    const SizedBox(height: 8),
                    ...lines.map(_lineCard),
                    const SizedBox(height: 12),
                    _returnSummary(),
                  ]),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                    onPressed: submitting ? null : _submitReturn,
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.assignment_return_outlined),
                    label: Text(submitting
                        ? 'جارٍ الترحيل...'
                        : 'ترحيل المرتجع الجزئي')))),
      );

  Widget _invoiceSummary() => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.receipt_long_rounded, color: Color(0xFF315CFF)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('فاتورة $number',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17))),
              _statusChip('قابلة للمرتجع', const Color(0xFF027A48))
            ]),
            const SizedBox(height: 14),
            Text('العميل: ${widget.invoice['customer_name']}'),
            const SizedBox(height: 5),
            Text(
                'إجمالي الفاتورة: ${(widget.invoice['total'] as num).toStringAsFixed(2)} ${widget.invoice['currency']}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ])));

  Widget _statusChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      );

  Widget _lineCard(Map<String, Object?> line) {
    final id = line['id']! as int;
    final remaining = _remaining(line);
    final selected = quantities[id] ?? 0;
    final current = _num(line['current_stock']);
    return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
            padding: const EdgeInsets.all(15),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(line['item_name']! as String,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                Text(
                    '${_format(_num(line['unit_price']))} ${widget.invoice['currency']}',
                    style: const TextStyle(fontWeight: FontWeight.bold))
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _metric('مباع', _num(line['sold_quantity'])),
                _metric('مرتجع سابق', _num(line['returned_quantity'])),
                _metric('متبقٍ', remaining, color: const Color(0xFF315CFF)),
                _metric('المخزون الحالي', current,
                    color: const Color(0xFF027A48)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(
                    child: Text('كمية هذا المرتجع',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(
                    width: 105,
                    child: TextField(
                        controller: controllers[id],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                            hintText: '0',
                            suffixText: '/ ${_format(remaining)}'),
                        onChanged: (value) {
                          quantities[id] = (double.tryParse(value) ?? 0)
                              .clamp(0, remaining)
                              .toDouble();
                          setState(() {});
                        })),
                IconButton(
                    onPressed: () => _setQuantity(id, selected - 1),
                    icon: const Icon(Icons.remove_circle_outline)),
                IconButton(
                    onPressed: () => _setQuantity(id, selected + 1),
                    icon: const Icon(Icons.add_circle_outline)),
              ]),
              if (selected > 0)
                Text(
                    'المخزون بعد المرتجع: ${_format(current + selected)}  •  قيمة السطر: ${_format(selected * _num(line['unit_price']))} ${widget.invoice['currency']}',
                    style: const TextStyle(
                        color: Color(0xFF027A48), fontSize: 12)),
            ])));
  }

  Widget _metric(String label, double value, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: (color ?? Colors.blueGrey).withAlpha(18),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$label: ${_format(value)}',
          style: TextStyle(
              color: color ?? Colors.blueGrey.shade700, fontSize: 12)));

  Widget _returnSummary() => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBBF7D0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ملخص المرتجع',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        _summaryRow('إجمالي الكمية', '${_format(returnQuantity)} وحدة'),
        _summaryRow('قيمة المرتجع',
            '${_format(returnTotal)} ${widget.invoice['currency']}'),
        _summaryRow('تكلفة البضاعة المعادة',
            '${_format(returnCost)} ${widget.invoice['currency']}'),
        const Divider(height: 20),
        _summaryRow('الربح المعكوس',
            '${_format(returnTotal - returnCost)} ${widget.invoice['currency']}',
            strong: true),
      ]));

  Widget _summaryRow(String label, String value, {bool strong = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight:
                            strong ? FontWeight.bold : FontWeight.normal))),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: strong ? const Color(0xFF027A48) : null))
          ]));
}
