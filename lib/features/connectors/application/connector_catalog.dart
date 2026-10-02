import '../../../connectors/connector_adapter.dart';
import '../domain/connector_item.dart';

class ConnectorCatalog {
  const ConnectorCatalog();

  List<ConnectorItem> get items => const [
        ConnectorItem(
          id: 'whatsapp_business',
          displayName: 'WhatsApp Business',
          description: 'استقبال إشعارات الأعمال عبر إعداد رسمي قابل للتدقيق.',
          category: 'المراسلة',
          featured: true,
          supportsMessages: true,
        ),
        ConnectorItem(
          id: 'sms',
          displayName: 'رسائل SMS',
          description: 'قراءة الإشعارات الواردة بعد منح إذن النظام على Android.',
          category: 'المراسلة',
          featured: true,
          supportsMessages: true,
        ),
        ConnectorItem(
          id: 'messenger',
          displayName: 'Messenger',
          description: 'موصل رسائل قابل للتوسعة عبر القنوات الرسمية.',
          category: 'المراسلة',
          supportsMessages: true,
        ),
        ConnectorItem(
          id: 'gmail',
          displayName: 'Gmail',
          description: 'تهيئة صندوق وارد للبريد مع مراجعة قبل إدخاله في السجل.',
          category: 'الإنتاجية',
          featured: true,
        ),
        ConnectorItem(
          id: 'google_drive',
          displayName: 'Google Drive',
          description: 'حفظ النسخ والتقارير في مساحة يحددها المستخدم.',
          category: 'الإنتاجية',
        ),
        ConnectorItem(
          id: 'google_calendar',
          displayName: 'تقويم Google',
          description: 'ربط مواعيد المتابعة والتنبيهات المالية عند إعداد الحساب.',
          category: 'الإنتاجية',
        ),
        ConnectorItem(
          id: 'notion',
          displayName: 'Notion',
          description: 'إرسال ملخصات أو صفحات متابعة بعد اعتماد المستخدم.',
          category: 'الإنتاجية',
        ),
        ConnectorItem(
          id: 'browser',
          displayName: 'المتصفح',
          description: 'فتح مسارات الويب من داخل التطبيق دون حفظ بيانات الدخول.',
          category: 'أدوات',
        ),
        ConnectorItem(
          id: 'instagram',
          displayName: 'Instagram',
          description: 'إضافة قابلة للإعداد للقنوات التجارية الرسمية فقط.',
          category: 'التسويق',
        ),
        ConnectorItem(
          id: 'bank_sandbox',
          displayName: 'بنك تجريبي Sandbox',
          description: 'حركات بنكية تجريبية آمنة لا تتصل ببنك حقيقي، مع ترحيل قابل للتكرار إلى حساب محاسبي.',
          category: 'البنوك',
          featured: true,
          implemented: true,
        ),
        ConnectorItem(
          id: 'webhook',
          displayName: 'Webhook مخصص',
          description: 'Endpoint آمن عبر HTTPS لتلقي الأحداث المصرح بها.',
          category: 'مخصص',
          requiresEndpoint: true,
        ),
      ];

  List<String> get categories => <String>['الكل', ...items.map((item) => item.category).toSet()];

  ConnectorStatus statusFor(String id, Set<String> connectedIds) =>
      connectedIds.contains(id)
          ? ConnectorStatus.connected
          : ConnectorStatus.disconnected;
}
