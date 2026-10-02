part of 'main.dart';

class _ConnectionStatusPill extends StatelessWidget {
  const _ConnectionStatusPill();

  @override
  Widget build(BuildContext context) {
    final local = ProductionConfig.localOnly;
    final configured = ProductionConfig.hasSyncEndpoint;
    final label = kIsWeb && ProductionConfig.webReviewMode
        ? 'معاينة محلية'
        : local
            ? 'محلي • SQLite'
            : configured
                ? 'مزامنة جاهزة'
                : 'متصل بدون مزامنة';
    final icon = local ? Icons.offline_bolt_rounded : Icons.cloud_done_rounded;
    final color = local ? WaselColors.success : WaselColors.primary;
    return Semantics(
      label: 'حالة التشغيل: $label',
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  bool showAccountingWorkspace = false;
  bool sidebarExpanded = true;
  final Set<int> favorites = {0, 1, 2};
  String displayName = 'المستخدم';
  bool storageReady = false;
  String? storageError;
  final accounting = AccountingRepository();
  late final ConnectorService connectorService;
  late final ConnectorCenterController connectorCenterController;
  late final AccountingReportsController accountingReportsController;
  late final WalletProvider walletProvider;
  List<Account> liveAccounts = [];
  FinancialSummary? financialSummary;
  String archiveQuery = '';
  String archiveSource = 'الكل';
  final entries = <Remittance>[];
  final titles = [
    'نظرة عامة',
    'الحوالات والأرشيف',
    'الحسابات',
    'محفظتي',
    'مشترياتي',
    'مبيعاتي والمخزون',
    'الإضافات',
    'الإعدادات',
  ];

  @override
  void initState() {
    super.initState();
    connectorService = ConnectorService(accounting);
    connectorCenterController = ConnectorCenterController(accounting)..load();
    accountingReportsController = AccountingReportsController(accounting);
    walletProvider = WalletProvider(WalletRepositoryImpl());
    _loadDisplayName();
    _hydrateEntries();
    _hydrateAccounting();
  }

  Future<void> _hydrateAccounting() async {
    await accounting.seedDefaultAccounts();
    final accounts = await accounting.accounts();
    final summary = await accounting.summary();
    if (mounted) {
      setState(() {
        liveAccounts = accounts;
        financialSummary = summary;
      });
    }
  }

  Future<void> _hydrateEntries() => _hydratePersistentEntries();

  Future<void> _hydratePersistentEntries() async {
    try {
      var stored = await LocalDatabase.instance.all();
      if (stored.isEmpty && _isWebReview) {
        for (final item in _webReviewEntries()) {
          await LocalDatabase.instance.insert(item);
        }
        stored = await LocalDatabase.instance.all();
      }
      if (!mounted) return;
      setState(() {
        entries
          ..clear()
          ..addAll(stored);
        storageReady = true;
        storageError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        storageReady = false;
        storageError = 'تعذر فتح قاعدة البيانات المحلية: $error';
      });
    }
  }

  Future<void> _loadDisplayName() async {
    try {
      final name = await AuthService().displayName();
      if (mounted && name.trim().isNotEmpty) {
        setState(() => displayName = name.trim());
      }
    } catch (_) {
      // A database preview remains usable if browser preferences reset.
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < WaselMetrics.compactBreakpoint;
          return Scaffold(
            body: compact
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                      child: _content(),
                    ),
                  )
                : Row(
                    children: [
                      _Sidebar(
                        expanded: sidebarExpanded,
                        selected: selected,
                        favorites: favorites,
                        onToggle: () =>
                            setState(() => sidebarExpanded = !sidebarExpanded),
                        onSelect: (i) => setState(() => selected = i),
                      ),
                      Expanded(
                        child: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              constraints.maxWidth > WaselMetrics.wideBreakpoint
                                  ? 32
                                  : 20,
                              24,
                              constraints.maxWidth > WaselMetrics.wideBreakpoint
                                  ? 32
                                  : 20,
                              20,
                            ),
                            child: _content(),
                          ),
                        ),
                      ),
                    ],
                  ),
            bottomNavigationBar: compact
                ? MobileAppNavigation(
                    selectedIndex: selected,
                    onSelect: (index) => setState(() => selected = index),
                  )
                : null,
          );
        },
      );

  Widget _content() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titles[selected],
                      style: TextStyle(
                        fontSize: MediaQuery.sizeOf(context).width <
                                WaselMetrics.compactBreakpoint
                            ? 22
                            : 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'مساحة عملك المالية، مرتبة وآمنة.',
                      style: TextStyle(
                        color: Colors.blueGrey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => selected = 6),
                tooltip: 'فتح سوق الإضافات والرسائل',
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              const SizedBox(width: 8),
              const _ConnectionStatusPill(),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE0E7FF),
                child: Text(
                  displayName.characters.first,
                  style: const TextStyle(
                    color: Color(0xFF315CFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_isWebReview) ...[
            const SizedBox(height: 14),
            _webReviewBanner(),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 28),
          Expanded(
            child: [
              _dashboard(),
              _archivePage(),
              _accountingPage(),
              _walletPage(),
              const MarketplaceScreen(),
              const MySalesDashboard(),
              _connectorsPage(),
              _settingsPage(),
            ][selected],
          ),
        ],
      );

  Widget _dashboard() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF172554), Color(0xFF315CFF)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isWebReview
                              ? 'معاينة تطبيق واصل'
                              : 'مساحة عملك المحلية جاهزة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.sizeOf(context).width < 520
                                ? 18
                                : 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isWebReview
                              ? 'بيانات تجريبية معزولة في هذا المتصفح. جرّب البحث والتصفية والإضافة مع حفظ SQLite حقيقي.'
                              : 'السجلات والحسابات محفوظة محليًا. لا توجد مزامنة أو قراءة إشعارات تلقائية في هذا البناء.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.tonal(
                          onPressed: () => setState(() => selected = 1),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF172554),
                          ),
                          child: const Text('استعراض الأرشيف'),
                        ),
                      ],
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width >= 520)
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFBFD0FF),
                      size: 76,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(children: _archiveDashboardStats()),
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'آخر العمليات المؤرشفة',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => selected = 1),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('فتح الأرشيف'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _entriesTable(),
          ],
        ),
      );

  Widget _archivePage() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArchiveToolbar(
            source: archiveSource,
            sources: _archiveSourceOptions(),
            onQueryChanged: (value) => setState(() => archiveQuery = value),
            onSourceChanged: (value) {
              if (value != null) setState(() => archiveSource = value);
            },
            onAdd: _showManualRemittanceDialog,
          ),
          const SizedBox(height: 18),
          Expanded(child: _entriesTable()),
        ],
      );

  Widget _accountingPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(
                () => showAccountingWorkspace = !showAccountingWorkspace,
              ),
              icon: Icon(
                showAccountingWorkspace
                    ? Icons.arrow_back_rounded
                    : Icons.account_tree_outlined,
              ),
              label: Text(
                showAccountingWorkspace
                    ? 'العودة إلى ملخص الحسابات'
                    : 'فتح دليل الحسابات',
              ),
            ),
          ),
          Expanded(
            child: showAccountingWorkspace
                ? AccountingWorkspaceScreen(repository: accounting)
                : _accountsPage(),
          ),
        ],
      );

  Widget _accountsPage() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = <Widget>[
                  _accountHero(
                    'الرصيد النقدي',
                    (financialSummary?.cashBalance ?? 0).toStringAsFixed(0),
                    'ريال سعودي',
                    Icons.account_balance_wallet_rounded,
                    const Color(0xFF315CFF),
                  ),
                  _accountHero(
                    'الرصيد البنكي',
                    (financialSummary?.bankBalance ?? 0).toStringAsFixed(0),
                    'ريال سعودي',
                    Icons.account_balance_rounded,
                    const Color(0xFF079455),
                  ),
                  _accountHero(
                    'القيود المسجلة',
                    (financialSummary?.vouchersCount ?? 0).toString(),
                    'قيد وسند',
                    Icons.insights_rounded,
                    const Color(0xFFF79009),
                  ),
                ];
                if (constraints.maxWidth < 760) {
                  return Column(
                    children: [
                      for (var index = 0; index < cards.length; index++) ...[
                        SizedBox(width: double.infinity, child: cards[index]),
                        if (index < cards.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var index = 0; index < cards.length; index++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: index < cards.length - 1 ? 14 : 0,
                          ),
                          child: cards[index],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _showVoucherDialog(VoucherType.receipt),
                  icon: const Icon(Icons.add_card),
                  label: const Text('سند قبض'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showVoucherDialog(VoucherType.payment),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('سند صرف'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showVoucherDialog(VoucherType.journal),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('قيد يومي'),
                ),
                OutlinedButton.icon(
                  onPressed: _showAccountDialog,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('إضافة حساب'),
                ),
                OutlinedButton.icon(
                  onPressed: _importAccounts,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('استيراد Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _showPartyDialog,
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('عميل / مورد'),
                ),
                OutlinedButton.icon(
                  onPressed: _openAccountingReports,
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('التقرير المالي'),
                ),
                OutlinedButton.icon(
                  onPressed: _showAudit,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('سجل التدقيق'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'شجرة الحسابات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${liveAccounts.length} حساب',
                  style: TextStyle(color: Colors.blueGrey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: _box(),
              child: liveAccounts.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'لا توجد حسابات بعد. أضف حسابًا أو استورد دليل الحسابات.',
                      ),
                    )
                  : Column(
                      children: liveAccounts
                          .map(
                            (a) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFEAF0FF),
                                child: Text(
                                  a.code.substring(
                                    0,
                                    a.code.length > 2 ? 2 : a.code.length,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF315CFF),
                                  ),
                                ),
                              ),
                              title: Text(
                                a.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${a.code}  •  ${a.type}  •  ${a.currency}',
                              ),
                              trailing: Text(
                                a.balance.toStringAsFixed(2),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      );
  Widget _walletPage() => MyWalletScreen(provider: walletProvider);

  Widget _connectorsPage() => ConnectorCenterScreen(
        controller: connectorCenterController,
        onSetup: (ConnectorItem item) {
          _showConnectorDialog(item);
        },
      );

  @override
  void dispose() {
    connectorCenterController.dispose();
    accountingReportsController.dispose();
    walletProvider.dispose();
    super.dispose();
  }

  Widget _settingsPage() => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Text(
            'الإعدادات والأمان',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              onTap: _showChangePasswordDialog,
              leading:
                  const Icon(Icons.password_outlined, color: Color(0xFF315CFF)),
              title: const Text('تغيير كلمة المرور',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('تحديث كلمة مرور هذا الجهاز'),
              trailing: const Icon(Icons.chevron_left),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint, color: WaselColors.muted),
              title: const Text('قفل الجلسة بالبصمة'),
              subtitle: const Text(
                  'غير مفعّل: لا يُعاد قفل الجلسة تلقائيًا عند مغادرة التطبيق.'),
              trailing:
                  const Icon(Icons.lock_outline, color: WaselColors.muted),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.backup_outlined, color: Color(0xFF315CFF)),
              title: const Text('النسخ الاحتياطي المشفّر',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                kIsWeb
                    ? 'نزّل نسخة AES/GCM بامتداد .wbackup أو اختر ملفًا لاستعادته.'
                    : 'احفظ نسخة AES/GCM محلية أو استعد ملف .wbackup.',
              ),
              trailing: Wrap(
                spacing: 6,
                children: [
                  IconButton(
                    tooltip: 'تنزيل/حفظ نسخة مشفرة',
                    onPressed: _backup,
                    icon: const Icon(Icons.save_alt),
                  ),
                  IconButton(
                    tooltip: 'استعادة ملف مشفر',
                    onPressed: _restore,
                    icon: const Icon(Icons.restore),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined,
                  color: WaselColors.muted),
              title: const Text('مزامنة الخادم'),
              subtitle: const Text(
                  'غير مهيّأة: تظل البيانات داخل قاعدة SQLite المحلية.'),
              trailing:
                  const Icon(Icons.lock_outline, color: WaselColors.muted),
            ),
          ),
          Card(
            child: ListTile(
              onTap: _showCompanyDialog,
              leading:
                  const Icon(Icons.business_outlined, color: Color(0xFF315CFF)),
              title: const Text('بيانات الشركة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle:
                  const Text('الاسم القانوني والرقم الضريبي وبيانات الطباعة'),
              trailing: const Icon(Icons.edit_outlined),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.language_rounded, color: WaselColors.muted),
              title: Text('اللغة والعملة'),
              subtitle: Text('العربية • تُحدّد العملة لكل حساب وعملية.'),
            ),
          ),
        ],
      );
  String _empty(String value, String fallback) =>
      value.trim().isEmpty ? fallback : value.trim();
  Widget _accountHero(
    String title,
    String value,
    String currency,
    IconData icon,
    Color color,
  ) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .75)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    currency,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  Widget _stat(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _box(),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.blueGrey.shade500,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  Widget _entriesTable() {
    final q = archiveQuery.trim().toLowerCase();
    final visible = entries
        .where(
          (e) =>
              (q.isEmpty ||
                  '${e.sender} ${e.phone} ${e.reference} ${e.message}'
                      .toLowerCase()
                      .contains(q)) &&
              (archiveSource == 'الكل' || e.source == archiveSource),
        )
        .toList();
    return Container(
      decoration: _box(),
      width: double.infinity,
      child: visible.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    q.isEmpty && archiveSource == 'الكل'
                        ? Icons.inbox_outlined
                        : Icons.search_off_rounded,
                    size: 34,
                    color: WaselColors.muted,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    q.isEmpty && archiveSource == 'الكل'
                        ? 'الأرشيف فارغ — أضف عملية لتظهر هنا.'
                        : 'لا توجد سجلات تطابق البحث والفلتر الحاليين.',
                    textAlign: TextAlign.center,
                  ),
                  if (q.isEmpty && archiveSource == 'الكل') ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _showManualRemittanceDialog,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة أول عملية'),
                    ),
                  ],
                ],
              ),
            )
          : Column(
              children: visible
                  .map(
                    (e) => ListTile(
                      onTap: () => _showRemittanceDetails(e),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEAF0FF),
                        child: Icon(
                          e.source == 'WhatsApp'
                              ? Icons.chat_bubble_rounded
                              : Icons.receipt_long_rounded,
                          color: const Color(0xFF315CFF),
                          size: 19,
                        ),
                      ),
                      title: Text(e.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${e.source}  •  ${e.formattedDate}',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              e.formattedAmount,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF079455),
                              ),
                            ),
                            Text(
                              'مرجع ${e.reference}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.blueGrey.shade400,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  BoxDecoration _box() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBF2)),
      );
}
