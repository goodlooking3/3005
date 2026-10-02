part of 'main.dart';

extension _HomeShellWebReview on _HomeShellState {
  bool get _isWebReview => kIsWeb && ProductionConfig.webReviewMode;

  List<Widget> _archiveDashboardStats() {
    final now = DateTime.now();
    final today = entries
        .where((entry) => DateUtils.isSameDay(entry.createdAt, now))
        .toList(growable: false);
    final receipts =
        today.where((entry) => entry.type == EntryType.receipt).length;
    return [
      _stat(
        'السجلات المخزنة',
        entries.length.toString(),
        Icons.inventory_2_outlined,
        WaselColors.primary,
      ),
      const SizedBox(width: 14),
      _stat(
        'عمليات اليوم',
        today.length.toString(),
        Icons.today_outlined,
        WaselColors.success,
      ),
      const SizedBox(width: 14),
      _stat(
        'مقبوضات اليوم',
        receipts.toString(),
        Icons.south_west_rounded,
        WaselColors.warning,
      ),
    ];
  }

  List<String> _archiveSourceOptions() {
    final values = entries.map((entry) => entry.source).toSet().toList()
      ..sort();
    return ['الكل', ...values];
  }

  Widget _webReviewBanner() {
    if (!_isWebReview) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFFFF7E6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, color: Color(0xFFB54708)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'معاينة محلية ببيانات تجريبية داخل هذا المتصفح فقط؛ لا يوجد اتصال بخادم أو مزامنة. لا تُدخل بيانات مالية حقيقية.',
              ),
            ),
            const SizedBox(width: 8),
            if (storageReady)
              const Icon(Icons.check_circle_outline, color: WaselColors.success)
            else if (storageError != null)
              const Icon(Icons.error_outline, color: Colors.red)
            else
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  List<Remittance> _webReviewEntries() {
    final now = DateTime.now();
    return [
      Remittance(
        createdAt: now.subtract(const Duration(minutes: 12)),
        sender: 'متجر النخبة',
        phone: '+967 777 123 456',
        amount: 185000,
        currency: 'YER',
        reference: '8492317',
        message: 'تم استلام حوالة تجريبية بمبلغ 185,000 ريال يمني.',
        source: 'WhatsApp',
      ),
      Remittance(
        createdAt: now.subtract(const Duration(hours: 1)),
        sender: 'أحمد محمد',
        phone: '+966 550 123 456',
        amount: 1250,
        currency: 'SAR',
        reference: '550281',
        message: 'إشعار إيداع تجريبي 1,250 ريال سعودي.',
        source: 'SMS',
      ),
      Remittance(
        createdAt: now.subtract(const Duration(days: 1)),
        sender: 'مؤسسة البناء الحديث',
        phone: '+967 711 555 901',
        amount: 420,
        currency: 'USD',
        reference: '773102',
        message: 'تم تحويل مبلغ تجريبي 420 دولارًا.',
        source: 'Messenger',
        type: EntryType.expense,
      ),
    ];
  }

  Future<void> _showRemittanceDetails(Remittance entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.sender),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('المبلغ', entry.formattedAmount),
              _detailRow('المرجع', entry.reference),
              _detailRow('رقم الهاتف', entry.phone),
              _detailRow('المصدر', entry.source),
              _detailRow(
                  'النوع', entry.type == EntryType.receipt ? 'قبض' : 'مصروف'),
              _detailRow('التاريخ', entry.formattedDate),
              const Divider(height: 24),
              Text(entry.message),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label)),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.start,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}
