import 'package:flutter/material.dart';

import '../../../core/connector_models.dart';
import '../application/connector_center_controller.dart';
import '../domain/connector_item.dart';
import 'connector_card.dart';
import 'message_details_sheet.dart';

class ConnectorCenterScreen extends StatefulWidget {
  final ConnectorCenterController controller;
  final ValueChanged<ConnectorItem> onSetup;

  const ConnectorCenterScreen({
    super.key,
    required this.controller,
    required this.onSetup,
  });

  @override
  State<ConnectorCenterScreen> createState() => _ConnectorCenterScreenState();
}

class _ConnectorCenterScreenState extends State<ConnectorCenterScreen> {
  int section = 0;
  String query = '';
  String category = 'الكل';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.loading && controller.connectors.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.connectors.isEmpty) {
      return Center(child: Text(controller.error!));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'مركز الموصلات والرسائل',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: controller.load,
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'أضف أدواتك وقنواتك إلى مساحة العمل، ثم فعّل ما تحتاجه فقط.',
          style: TextStyle(color: Colors.blueGrey.shade500),
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.hub_outlined),
                label: Text('الإضافات'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.inbox_outlined),
              label: Text('صندوق الرسائل'),
            ),
          ],
          selected: {section},
          onSelectionChanged: (value) => setState(() => section = value.first),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: section == 0 ? _connectors(controller) : _messages(controller),
        ),
      ],
    );
  }

  Widget _connectors(ConnectorCenterController controller) {
    final normalized = query.trim().toLowerCase();
    final visible = controller.connectors.where((item) {
      final matchesCategory = category == 'الكل' || item.category == category;
      final haystack = '${item.displayName} ${item.description} ${item.category}'.toLowerCase();
      return matchesCategory && (normalized.isEmpty || haystack.contains(normalized));
    }).toList();
    final showFeatured = category == 'الكل' && normalized.isEmpty;
    final featured = showFeatured ? visible.where((item) => item.featured).toList() : const <ConnectorItem>[];
    final listItems = showFeatured ? visible.where((item) => !item.featured).toList() : visible;
    return Column(
      children: [
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث في الإضافات ومصادر البيانات',
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: controller.catalog.categories
                .map((item) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(item),
                        selected: category == item,
                        onSelected: (_) => setState(() => category = item),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        if (featured.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('إضافات مقترحة', style: Theme.of(context).textTheme.titleMedium),
          ),
        if (featured.isNotEmpty)
          ...featured.map(_connectorCard),
        Expanded(
          child: listItems.isEmpty
              ? const Center(child: Text('لا توجد إضافات مطابقة للبحث.'))
              : ListView(
                  children: listItems
                      .map(_connectorCard)
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _connectorCard(ConnectorItem item) => ConnectorCard(
        item: item,
        onSetup: () => widget.onSetup(item),
        onSync: item.id == 'bank_sandbox' ? () => _runBankAction(widget.controller.syncBankSandbox, 'جلب الحركات') : null,
        onPost: item.id == 'bank_sandbox' ? () => _runBankAction(widget.controller.postBankSandbox, 'الترحيل المحاسبي') : null,
      );

  Future<void> _runBankAction(Future<int> Function() action, String label) async {
    try {
      final count = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: تمت معالجة $count حركة')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ $label: $error')),
      );
    }
  }

  Widget _messages(ConnectorCenterController controller) {
    final visible = controller.messages.where((message) {
      final value =
          '${message.sender} ${message.provider} ${message.body}'.toLowerCase();
      return query.trim().isEmpty || value.contains(query.trim().toLowerCase());
    }).toList();
    return Column(
      children: [
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث في الرسائل الواردة',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _showImportDialog(controller),
            icon: const Icon(Icons.input_rounded),
            label: const Text('استيراد رسالة وتحليلها'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Text('لا توجد رسائل واردة تحتاج إلى معالجة.'),
                )
              : ListView(
                  children: visible
                      .map((message) => _messageTile(controller, message))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _showImportDialog(ConnectorCenterController controller) async {
    final sender = TextEditingController();
    final phone = TextEditingController();
    final body = TextEditingController();
    var provider = 'SMS';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استيراد رسالة'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: provider,
                decoration: const InputDecoration(labelText: 'المصدر'),
                items: const ['SMS', 'WhatsApp', 'Messenger']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) => provider = value ?? 'SMS',
              ),
              TextField(
                controller: sender,
                decoration: const InputDecoration(labelText: 'اسم المرسل'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(
                  labelText: 'الهاتف (اختياري)',
                ),
              ),
              TextField(
                controller: body,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'نص الرسالة'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (sender.text.trim().isEmpty || body.text.trim().isEmpty) {
                return;
              }
              await controller.importMessage(
                provider: provider,
                sender: sender.text,
                phone: phone.text,
                body: body.text,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('استيراد وتحليل'),
          ),
        ],
      ),
    );
    sender.dispose();
    phone.dispose();
    body.dispose();
  }

  Widget _messageTile(
    ConnectorCenterController controller,
    IncomingMessage message,
  ) =>
      Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFEAF0FF),
            child: Icon(_iconFor(message.provider),
                color: const Color(0xFF315CFF)),
          ),
          title: Text(
            message.sender,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${message.provider} • ${message.body}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _showDetails(controller, message),
          trailing: IconButton(
            tooltip: 'أرشفة',
            onPressed: () => controller.archive(message),
            icon: const Icon(Icons.archive_outlined),
          ),
        ),
      );

  Future<void> _showDetails(
    ConnectorCenterController controller,
    IncomingMessage message,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => MessageDetailsSheet(
        message: message,
        accountNames: controller.accountNames,
        onPost: (type, debit, credit, amount, currency, description) =>
            controller.postAndArchive(
          message,
          type,
          debit,
          credit,
          amount,
          currency,
          description,
        ),
      ),
    );
  }

  IconData _iconFor(String provider) => switch (provider) {
        'whatsapp_business' || 'WhatsApp' => Icons.chat_rounded,
        'sms' || 'SMS' => Icons.sms_outlined,
        'messenger' || 'Messenger' => Icons.forum_outlined,
        _ => Icons.mail_outline_rounded,
      };
}
