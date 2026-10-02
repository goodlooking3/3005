import 'package:flutter/material.dart';

import '../../../connectors/connector_adapter.dart';
import '../domain/connector_item.dart';

class ConnectorCard extends StatelessWidget {
  final ConnectorItem item;
  final VoidCallback onSetup;
  final VoidCallback? onSync;
  final VoidCallback? onPost;

  const ConnectorCard({super.key, required this.item, required this.onSetup, this.onSync, this.onPost});

  static const _icons = {
    'whatsapp_business': Icons.chat_rounded,
    'sms': Icons.sms_outlined,
    'messenger': Icons.forum_outlined,
    'gmail': Icons.mail_outline_rounded,
    'google_drive': Icons.cloud_outlined,
    'google_calendar': Icons.calendar_month_outlined,
    'notion': Icons.view_agenda_outlined,
    'browser': Icons.language_rounded,
    'instagram': Icons.camera_alt_outlined,
    'bank_sandbox': Icons.account_balance_outlined,
    'webhook': Icons.webhook_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final connected = item.status == ConnectorStatus.connected;
    final statusLabel = connected && !item.implemented
        ? 'إعداد محفوظ — بانتظار الربط الرسمي'
        : item.status.arabicLabel;
    final color = connected && item.implemented
        ? const Color(0xFF079455)
        : const Color(0xFF315CFF);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: .1),
              child: Icon(_icons[item.id] ?? Icons.extension_outlined, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      if (item.featured)
                        const Icon(Icons.star_rounded, size: 17, color: Color(0xFFF59E0B)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 7),
                  Text('${item.category} • $statusLabel',
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onSetup, child: Text(connected ? 'إدارة' : item.actionLabel)),
                if (item.id == 'bank_sandbox' && connected) ...[
                  TextButton(onPressed: onSync, child: const Text('جلب الحركات')),
                  TextButton(onPressed: onPost, child: const Text('ترحيل محاسبي')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
