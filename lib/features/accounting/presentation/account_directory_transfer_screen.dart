import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/user_facing_errors.dart';
import '../../../data/accounting_repository.dart';
import '../../../services/account_export_service.dart';
import '../../../services/account_import_service.dart';
import '../application/chart_account_catalog.dart';

class AccountDirectoryTransferScreen extends StatefulWidget {
  final AccountingRepository repository;
  const AccountDirectoryTransferScreen({super.key, required this.repository});

  @override
  State<AccountDirectoryTransferScreen> createState() => _AccountDirectoryTransferScreenState();
}

class _AccountDirectoryTransferScreenState extends State<AccountDirectoryTransferScreen> {
  final exporter = const AccountExportService();
  late final AccountImportService importer;
  late final ChartAccountCatalog catalog;
  bool loading = false;
  String message = 'اختر استيرادًا أو تصديرًا لدليل الحسابات';

  @override
  void initState() {
    super.initState();
    importer = AccountImportService(widget.repository);
    catalog = ChartAccountCatalog(widget.repository);
  }

  Future<void> _ensureDefaults() async {
    setState(() => loading = true);
    try {
      final accounts = await catalog.ensureDefaults();
      _show('تم تجهيز ${accounts.length} حسابًا، وتشمل الحسابات الرئيسية الأربعة');
    } catch (error) {
      _show(userFacingError(error,
          fallback: 'تعذر تجهيز الحسابات الرئيسية. حاول مجددًا'));
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    setState(() => loading = true);
    try {
      final outcome = await importer.importXlsx(bytes);
      _show('استوردنا ${outcome.imported} حسابًا وتجاوزنا ${outcome.skipped} صفًا');
      if (outcome.errors.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('تفاصيل الاستيراد'),
            content: SingleChildScrollView(child: Text(outcome.errors.join('\n'))),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
          ),
        );
      }
    } catch (error) {
      _show(userFacingError(error,
          fallback: 'تعذر استيراد الملف. راجع الأعمدة وحاول مجددًا'));
    }
  }

  Future<void> _export() async {
    setState(() => loading = true);
    try {
      final accounts = await widget.repository.accounts(includeInactive: true);
      final bytes = exporter.buildXlsx(accounts);
      final path = await FilePicker.saveFile(
        fileName: 'wasel-chart-of-accounts.xlsx',
        bytes: Uint8List.fromList(bytes),
      );
      _show(path == null ? 'تم إلغاء التصدير' : 'تم تصدير الدليل إلى الملف المحدد');
    } catch (error) {
      _show(userFacingError(error,
          fallback: 'تعذر تصدير الدليل. حاول مجددًا'));
    }
  }

  void _show(String value) {
    if (!mounted) return;
    setState(() {
      loading = false;
      message = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('استيراد وتصدير دليل الحسابات')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('نموذج XLSX موحد', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('الأعمدة: code, name, type, kind, parent_code, is_group, currency, currencies, opening_balance, active'),
                    const SizedBox(height: 20),
                    FilledButton.icon(onPressed: loading ? null : _ensureDefaults, icon: const Icon(Icons.account_tree_outlined), label: const Text('تجهيز الحسابات الرئيسية الافتراضية')),
                    OutlinedButton.icon(onPressed: loading ? null : _import, icon: const Icon(Icons.upload_file), label: const Text('استيراد دليل XLSX')),
                    OutlinedButton.icon(onPressed: loading ? null : _export, icon: const Icon(Icons.download), label: const Text('تصدير الدليل XLSX')),
                    if (loading) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
                    const SizedBox(height: 16),
                    Text(message),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
