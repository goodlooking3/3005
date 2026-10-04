part of 'main.dart';

extension _HomeShellAccountActions on _HomeShellState {
  Future<void> _showAccountDialog() async {
    try {
      final accounts = await accounting.accounts(includeInactive: true);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) =>
            AccountEditorDialog(repository: accounting, accounts: accounts),
      );
      if (saved == true) await _hydrateAccounting();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
          content: Text('تعذر فتح محرر الحساب. حاول مجددًا'),
        ));
      }
    }
  }

  Future<void> _importAccounts() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) return;
    final result = await AccountImportService(accounting).importXlsx(bytes);
    await _hydrateAccounting();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم استيراد ${result.imported} حساب وتجاوز ${result.skipped}',
          ),
        ),
      );
    }
  }

  Future<void> _showPartyDialog() async {
    final accounts = await accounting.accounts();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => PartyEditorDialog(
        repository: accounting,
        accounts: accounts,
      ),
    );
    if (saved == true) await _hydrateAccounting();
  }

  Future<void> _showCompanyDialog() async {
    final current = await accounting.company();
    final name = TextEditingController(text: current?.name);
    final legal = TextEditingController(text: current?.legalName);
    final tax = TextEditingController(text: current?.taxNumber);
    final phone = TextEditingController(text: current?.phone);
    final address = TextEditingController(text: current?.address);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بيانات الشركة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم الشركة'),
              ),
              TextField(
                controller: legal,
                decoration: const InputDecoration(labelText: 'الاسم القانوني'),
              ),
              TextField(
                controller: tax,
                decoration: const InputDecoration(labelText: 'الرقم الضريبي'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'الهاتف'),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'العنوان'),
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
              if (name.text.trim().isEmpty) return;
              await accounting.saveCompany(
                CompanyProfile(
                  name: name.text,
                  legalName: legal.text,
                  taxNumber: tax.text,
                  phone: phone.text,
                  address: address.text,
                ),
              );
              await accounting.log('update_company_profile', name.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ البيانات'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConnectorDialog(ConnectorItem connector) async {
    final endpoint = TextEditingController();
    final qr = TextEditingController(
      text: connector.id == 'whatsapp_business'
          ? 'wasel://whatsapp/connect/${DateTime.now().millisecondsSinceEpoch}'
          : '',
    );
    final bankAccounts = liveAccounts
        .where(
          (account) =>
              account.kind == AccountKind.bank &&
              account.active &&
              account.supportedCurrencies.contains('SAR'),
        )
        .toList(growable: false);
    Account? linkedBank = bankAccounts.isEmpty ? null : bankAccounts.first;
    var enabled = connector.status == ConnectorStatus.connected;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('إدارة إضافة ${connector.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!ProductionConfig.localOnly)
                TextField(
                  controller: endpoint,
                  decoration: InputDecoration(
                    labelText: connector.requiresEndpoint
                        ? 'Endpoint HTTPS (مطلوب)'
                        : 'Endpoint HTTPS (اختياري)',
                  ),
                ),
              if (ProductionConfig.localOnly)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'الوضع المحلي مفعّل: تحفظ البيانات على هذا الجهاز فقط، ولا يتم الاتصال بخادم خارجي.\nلا تُعد الإضافة متصلة فعليًا حتى تُضبط بياناتها الرسمية.',
                  ),
                ),
              TextField(
                controller: qr,
                decoration: const InputDecoration(
                  labelText: 'بيانات الربط أو رمز الجلسة (اختياري)',
                ),
              ),
              if (connector.id == 'bank_sandbox')
                DropdownButtonFormField<Account>(
                  initialValue: linkedBank,
                  decoration: const InputDecoration(
                    labelText: 'الحساب البنكي المحاسبي',
                  ),
                  items: bankAccounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account,
                          child: Text(
                            '${account.code} — ${account.name} (${account.currency})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setLocal(() => linkedBank = value),
                ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      final opened = await AndroidNotificationService()
                          .openListenerSettings();
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تعذر فتح إعدادات إشعارات Android'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('فتح صلاحية قراءة الإشعارات'),
                  ),
                ),
              SwitchListTile(
                value: enabled,
                onChanged: (value) => setLocal(() => enabled = value),
                title: const Text('تفعيل الإضافة'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await connectorService.saveSetup(
                    connector: connector,
                    endpoint: endpoint.text,
                    qrPayload: qr.text,
                    enabled: enabled,
                    linkedAccountId: linkedBank?.id,
                  );
                } on FormatException catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.message)));
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                await connectorCenterController.load();
              },
              child: const Text('حفظ وتفعيل'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAccountingReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AccountingReportsScreen(controller: accountingReportsController),
      ),
    );
  }

  Future<void> _showAudit() async {
    final records = await accounting.audit();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('سجل التدقيق'),
        content: SizedBox(
          width: 420,
          child: records.isEmpty
              ? const Text('لا توجد عمليات مسجلة بعد.')
              : ListView(
                  shrinkWrap: true,
                  children: records
                      .take(20)
                      .map(
                        (r) => ListTile(
                          dense: true,
                          title: Text(r.action),
                          subtitle: Text(r.details),
                        ),
                      )
                      .toList(),
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
}
