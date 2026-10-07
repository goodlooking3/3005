import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/user_facing_errors.dart';
import '../../../data/accounting_authorization.dart';
import '../../../data/accounting_policy_repository.dart';
import '../../../data/accounting_period_repository.dart';
import '../../../data/local_database.dart';

class AccountingPeriodsDialog extends StatefulWidget {
  final AccountingPeriodRepository repository;

  const AccountingPeriodsDialog({
    super.key,
    this.repository = const AccountingPeriodRepository(),
  });

  @override
  State<AccountingPeriodsDialog> createState() =>
      _AccountingPeriodsDialogState();
}

class _AccountingPeriodsDialogState extends State<AccountingPeriodsDialog> {
  List<Map<String, Object?>> periods = const [];
  bool loading = true;
  bool busy = false;
  bool canManage = false;
  bool canClose = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final db = await LocalDatabase.instance.database;
      final manage = await AccountingAuthorization.instance
          .can(db, AccountingPermission.managePeriods);
      final close = await AccountingAuthorization.instance
          .can(db, AccountingPermission.closePeriods);
      final values = await widget.repository.periods();
      if (!mounted) return;
      setState(() {
        canManage = manage;
        canClose = close;
        periods = values;
        loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => loading = false);
        _message(
            userFacingError(error, fallback: 'تعذر تحميل الفترات المالية'));
      }
    }
  }

  Future<void> _create() async {
    final now = DateTime.now();
    final policy = await const AccountingPolicyRepository().load();
    if (!mounted) return;
    final fiscalStartYear = now.month >= policy.fiscalYearStartMonth
        ? now.year
        : now.year - 1;
    final fiscalStart = DateTime(fiscalStartYear, policy.fiscalYearStartMonth);
    final fiscalEnd = DateTime(fiscalStartYear + 1, policy.fiscalYearStartMonth)
        .subtract(const Duration(days: 1));
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(
        start: fiscalStart,
        end: fiscalEnd,
      ),
      helpText: 'حدد نطاق الفترة المالية',
    );
    if (range == null || !mounted) return;
    final start = _date(range.start);
    final end = _date(range.end);
    setState(() => busy = true);
    try {
      await widget.repository.createPeriod(
        name: '$start — $end',
        startDate: range.start,
        endDate: range.end,
      );
      await _load();
    } catch (error) {
      _message(userFacingError(error, fallback: 'تعذر إنشاء الفترة المالية'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _close(Map<String, Object?> period) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إقفال الفترة المالية'),
        content: Text(
          'سيُمنع ترحيل أي قيد جديد إلى فترة ${period['name']}، ولا يمكن إعادة فتحها. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إقفال نهائي'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.closePeriod(period['id']! as int);
      await _load();
    } catch (error) {
      _message(userFacingError(error, fallback: 'تعذر إقفال الفترة'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _date(Object? value) {
    final date = DateTime.parse(value! as String);
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('الفترات المالية')),
          if (canManage)
            IconButton(
              tooltip: 'إنشاء فترة مالية',
              onPressed: busy ? null : _create,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      content: SizedBox(
        width: size.width < 720 ? size.width * 0.86 : 620,
        height: size.height < 600 ? size.height * 0.62 : 380,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : periods.isEmpty
                ? const Center(
                    child: Text(
                        'لا توجد فترات معرفة؛ الترحيل مفتوح دون قيد زمني.'),
                  )
                : ListView.separated(
                    itemCount: periods.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final period = periods[index];
                      final open = period['status'] == 'open';
                      return ListTile(
                        title: Text(period['name']! as String),
                        subtitle: Text(
                          '${_date(period['start_date'])} إلى ${_date(period['end_date'])}',
                        ),
                        trailing: open && canClose
                            ? IconButton(
                                tooltip: 'إقفال الفترة بعد التحقق من الاتزان',
                                onPressed: busy ? null : () => _close(period),
                                icon: const Icon(Icons.lock_outline),
                              )
                            : Chip(label: Text(open ? 'مفتوحة' : 'مقفلة')),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
