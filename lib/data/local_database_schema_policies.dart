part of 'local_database_schema.dart';

Future<void> _ensureAccountingPolicySettings(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS accounting_policy_settings (
      policy_key TEXT PRIMARY KEY,
      policy_value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  const defaults = <String, String>{
    'reporting_framework': 'general',
    'aging_date_basis': 'due_date_when_available',
    'fiscal_year_start_month': '1',
    'jurisdiction_code': '',
    'comparative_period_basis': 'previous_period',
  };
  final now = DateTime.now().toUtc().toIso8601String();
  for (final entry in defaults.entries) {
    await db.insert(
      'accounting_policy_settings',
      {
        'policy_key': entry.key,
        'policy_value': entry.value,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
