import 'package:sqflite/sqflite.dart';

import 'accounting_authorization.dart';
import 'local_database.dart';

enum AgingDateBasis { dueDateWhenAvailable, postingDateOnly, dueDateOnly }

enum ReportingFramework { general, ifrs, local }

class AccountingPolicySettings {
  final ReportingFramework reportingFramework;
  final AgingDateBasis agingDateBasis;
  final int fiscalYearStartMonth;
  final String jurisdictionCode;

  const AccountingPolicySettings({
    this.reportingFramework = ReportingFramework.general,
    this.agingDateBasis = AgingDateBasis.dueDateWhenAvailable,
    this.fiscalYearStartMonth = 1,
    this.jurisdictionCode = '',
  });
}

class AccountingPolicyRepository {
  const AccountingPolicyRepository();

  static const defaults = <String, String>{
    'reporting_framework': 'general',
    'aging_date_basis': 'due_date_when_available',
    'fiscal_year_start_month': '1',
    'jurisdiction_code': '',
  };

  Future<AccountingPolicySettings> load() async {
    final db = await LocalDatabase.instance.database;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query('accounting_policy_settings');
    final values = {
      ...defaults,
      for (final row in rows)
        row['policy_key']! as String: row['policy_value']! as String
    };
    final framework = ReportingFramework.values.firstWhere(
      (value) => value.name == values['reporting_framework'],
      orElse: () => ReportingFramework.general,
    );
    final aging = switch (values['aging_date_basis']) {
      'posting_date_only' => AgingDateBasis.postingDateOnly,
      'due_date_only' => AgingDateBasis.dueDateOnly,
      _ => AgingDateBasis.dueDateWhenAvailable,
    };
    final month = int.tryParse(values['fiscal_year_start_month'] ?? '') ?? 1;
    return AccountingPolicySettings(
      reportingFramework: framework,
      agingDateBasis: aging,
      fiscalYearStartMonth: month >= 1 && month <= 12 ? month : 1,
      jurisdictionCode: values['jurisdiction_code'] ?? '',
    );
  }

  Future<void> save(AccountingPolicySettings settings) async {
    if (settings.fiscalYearStartMonth < 1 ||
        settings.fiscalYearStartMonth > 12) {
      throw ArgumentError('شهر بداية السنة المالية غير صالح');
    }
    final jurisdiction = settings.jurisdictionCode.trim().toUpperCase();
    if (settings.reportingFramework == ReportingFramework.local &&
        !RegExp(r'^[A-Z]{2}$').hasMatch(jurisdiction)) {
      throw ArgumentError('أدخل رمز بلد من حرفين عند اختيار المعيار المحلي');
    }
    await LocalDatabase.instance.write((db) async {
      await db.transaction((txn) async {
        await AccountingAuthorization.instance
            .require(txn, AccountingPermission.manageCompanySettings);
        final values = {
          'reporting_framework': settings.reportingFramework.name,
          'aging_date_basis': switch (settings.agingDateBasis) {
            AgingDateBasis.dueDateWhenAvailable => 'due_date_when_available',
            AgingDateBasis.postingDateOnly => 'posting_date_only',
            AgingDateBasis.dueDateOnly => 'due_date_only',
          },
          'fiscal_year_start_month': '${settings.fiscalYearStartMonth}',
          'jurisdiction_code': jurisdiction,
        };
        for (final entry in values.entries) {
          await txn.insert(
            'accounting_policy_settings',
            {
              'policy_key': entry.key,
              'policy_value': entry.value,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    });
  }
}
