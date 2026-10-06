import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/user_facing_errors.dart';
import '../../../data/accounting_policy_repository.dart';

class AccountingPolicySettingsDialog extends StatefulWidget {
  final AccountingPolicyRepository repository;

  const AccountingPolicySettingsDialog({
    super.key,
    this.repository = const AccountingPolicyRepository(),
  });

  @override
  State<AccountingPolicySettingsDialog> createState() =>
      _AccountingPolicySettingsDialogState();
}

class _AccountingPolicySettingsDialogState
    extends State<AccountingPolicySettingsDialog> {
  AccountingPolicySettings settings = const AccountingPolicySettings();
  late final TextEditingController jurisdiction;
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    jurisdiction = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    jurisdiction.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.repository.load();
      if (mounted) {
        setState(() {
          settings = loaded;
          jurisdiction.text = loaded.jurisdictionCode;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = userFacingError(
              exception,
              fallback: 'تعذر تحميل السياسات المحاسبية',
            ));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.save(settings);
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() => error = userFacingError(
              exception,
              fallback: 'تعذر حفظ السياسات المحاسبية',
            ));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('السياسات المحاسبية العامة'),
      content: SizedBox(
        width: width < 720 ? width * .86 : 620,
        child: loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    DropdownButtonFormField<ReportingFramework>(
                      value: settings.reportingFramework,
                      decoration: const InputDecoration(
                        labelText: 'إطار التقارير المفضل',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ReportingFramework.general,
                          child: Text('سياسة عامة — غير منسوبة لمعيار'),
                        ),
                        DropdownMenuItem(
                          value: ReportingFramework.ifrs,
                          child: Text('IFRS — تفضيل عرض، لا شهادة امتثال'),
                        ),
                        DropdownMenuItem(
                          value: ReportingFramework.local,
                          child: Text('معيار محلي — أدخل رمز البلد'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() {
                                settings = _copy(
                                  framework:
                                      value ?? settings.reportingFramework,
                                );
                                if (value == ReportingFramework.local) {
                                  jurisdiction.text = settings.jurisdictionCode;
                                }
                              }),
                    ),
                    if (settings.reportingFramework == ReportingFramework.local)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: jurisdiction,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: const InputDecoration(
                            labelText: 'رمز البلد (ISO 3166-1 alpha-2)',
                            hintText: 'مثال: SA، EG، AE',
                          ),
                          onChanged: (value) => setState(() => settings = _copy(
                                jurisdictionCode: value,
                              )),
                        ),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AgingDateBasis>(
                      value: settings.agingDateBasis,
                      decoration: const InputDecoration(
                        labelText: 'أساس أعمار الذمم',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: AgingDateBasis.dueDateWhenAvailable,
                          child: Text('الاستحقاق إن وجد؛ وإلا تاريخ القيد'),
                        ),
                        DropdownMenuItem(
                          value: AgingDateBasis.postingDateOnly,
                          child: Text('تاريخ القيد دائمًا'),
                        ),
                        DropdownMenuItem(
                          value: AgingDateBasis.dueDateOnly,
                          child: Text('الاستحقاق فقط؛ بلا تاريخ يظهر غير مؤرخ'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() => settings = _copy(
                                aging: value ?? settings.agingDateBasis,
                              )),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: settings.fiscalYearStartMonth,
                      decoration: const InputDecoration(
                        labelText: 'شهر بداية السنة المالية',
                      ),
                      items: List.generate(
                        12,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text(_months[index]),
                        ),
                      ),
                      onChanged: saving
                          ? null
                          : (value) => setState(() => settings = _copy(
                                month: value ?? settings.fiscalYearStartMonth,
                              )),
                    ),
                    const SizedBox(height: 16),
                    const _PolicyNotice(
                      title: 'العملة المحلية',
                      body:
                          'تُختار من «بيانات الشركة». لا يسمح النظام بتغييرها بعد ترحيل القيود حتى لا تختلط أرصدة بعملات أساس مختلفة.',
                    ),
                    const _PolicyNotice(
                      title: 'الضريبة والمخزون والأصول',
                      body:
                          'المخزون يستخدم حاليًا المتوسط المرجح. الضرائب تبقى معطلة حتى تهيئة ملف بلد وحسابات ضريبية. لا تتوفر وحدة أصول ثابتة بعد. لن يظهر اختيار غير مدعوم كأنه مطبق؛ تضاف البدائل بعد تنفيذ محركاتها.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختيار IFRS أو معيار محلي يحفظ تفضيل المنشأة فقط؛ لا يعني أن جميع متطلبات ذلك المعيار مطبقة أو معتمدة.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        FilledButton(
          onPressed: loading || saving ? null : _save,
          child: Text(saving ? 'جارٍ الحفظ…' : 'حفظ السياسات'),
        ),
      ],
    );
  }

  AccountingPolicySettings _copy({
    ReportingFramework? framework,
    AgingDateBasis? aging,
    int? month,
    String? jurisdictionCode,
  }) =>
      AccountingPolicySettings(
        reportingFramework: framework ?? settings.reportingFramework,
        agingDateBasis: aging ?? settings.agingDateBasis,
        fiscalYearStartMonth: month ?? settings.fiscalYearStartMonth,
        jurisdictionCode: jurisdictionCode ?? settings.jurisdictionCode,
      );

  static const _months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
}

class _PolicyNotice extends StatelessWidget {
  final String title;
  final String body;

  const _PolicyNotice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(title),
          subtitle: Text(body),
          isThreeLine: true,
        ),
      );
}
