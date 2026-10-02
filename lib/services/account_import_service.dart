import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/accounting.dart';
import '../data/accounting_repository.dart';

class AccountImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;
  const AccountImportResult({required this.imported, required this.skipped, this.errors = const []});
}

class AccountImportService {
  final AccountingRepository repository;
  const AccountImportService(this.repository);

  Future<AccountImportResult> importXlsx(Uint8List bytes) async {
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables.isEmpty ? null : workbook.tables.values.first;
    if (sheet == null || sheet.rows.isEmpty) throw const FormatException('ملف Excel فارغ');
    final headers = sheet.rows.first
        .map<String>((cell) => cell?.value.toString().trim().toLowerCase() ?? '')
        .toList();
    final codeIndex = _first(headers, ['code', 'الكود']);
    final nameIndex = _first(headers, ['name', 'الاسم']);
    if (codeIndex < 0 || nameIndex < 0) throw const FormatException('يجب أن يحتوي الملف على عمودي الكود والاسم');
    var imported = 0;
    var skipped = 0;
    final errors = <String>[];
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final code = _value(row, codeIndex);
      final name = _value(row, nameIndex);
      if (code.isEmpty || name.isEmpty) {
        skipped++;
        errors.add('السطر ${rowIndex + 1}: الكود والاسم مطلوبان');
        continue;
      }
      try {
        final parentCode = _value(row, _first(headers, ['parent_code', 'كود الأب']));
        final parent = parentCode.isEmpty ? null : await repository.accountByCode(parentCode);
        await repository.upsertAccount(Account(
          code: code,
          name: name,
          type: _value(row, _first(headers, ['type', 'النوع'])),
          kind: _kind(_value(row, _first(headers, ['kind', 'التصنيف']))),
          parentId: parent?.id,
          isGroup: _trueValue(_value(row, _first(headers, ['is_group', 'تجميعي']))),
          currency: _value(row, _first(headers, ['currency', 'العملة'])).ifEmpty('SAR').toUpperCase(),
          currencies: _currencies(row, headers),
          balance: double.tryParse(_value(row, _first(headers, ['opening_balance', 'الرصيد الافتتاحي']))) ?? 0,
          active: _activeValue(_value(row, _first(headers, ['active', 'نشط']))),
        ));
        imported++;
      } catch (error) {
        skipped++;
        errors.add('السطر ${rowIndex + 1}: تعذر الحفظ ($error)');
      }
    }
    await repository.log('import_accounts', 'imported=$imported skipped=$skipped');
    return AccountImportResult(imported: imported, skipped: skipped, errors: errors);
  }

  int _first(List<String> headers, List<String> names) {
    for (final name in names) {
      final index = headers.indexOf(name);
      if (index >= 0) return index;
    }
    return -1;
  }

  String _value(List<Data?> row, int index) => index >= 0 && index < row.length ? (row[index]?.value?.toString().trim() ?? '') : '';
  List<String> _currencies(List<Data?> row, List<String> headers) {
    final values = _value(row, _first(headers, ['currencies', 'العملات']))
        .split(',')
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (values.isNotEmpty) return values;
    return [_value(row, _first(headers, ['currency', 'العملة'])).ifEmpty('SAR')];
  }
  bool _trueValue(String value) => value == '1' || value.toLowerCase() == 'true' || value == 'تجميعي';
  bool _activeValue(String value) => value.isEmpty || !_falseValue(value);
  bool _falseValue(String value) => value == '0' || value.toLowerCase() == 'false' || value == 'متوقف';
  AccountKind _kind(String value) => AccountKind.values.firstWhere((k) => k.name == value || k.name == _translate(value), orElse: () => AccountKind.asset);
  String _translate(String value) => {'أصل': 'asset', 'التزام': 'liability', 'حقوق ملكية': 'equity', 'إيراد': 'revenue', 'مصروف': 'expense', 'صندوق': 'cash', 'بنك': 'bank', 'عميل': 'customer', 'مورد': 'supplier'}[value] ?? value;
}

extension _StringDefault on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
