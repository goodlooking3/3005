import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/accounting.dart';

class AccountExportService {
  const AccountExportService();

  Uint8List buildXlsx(Iterable<Account> accounts) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('code'),
      TextCellValue('name'),
      TextCellValue('name_ar'),
      TextCellValue('name_en'),
      TextCellValue('type'),
      TextCellValue('kind'),
      TextCellValue('parent_code'),
      TextCellValue('is_group'),
      TextCellValue('currency'),
      TextCellValue('currencies'),
      TextCellValue('opening_balance'),
      TextCellValue('active'),
    ]);
    final byId = {for (final account in accounts) account.id: account};
    for (final account in accounts) {
      sheet.appendRow([
        TextCellValue(account.code),
        TextCellValue(account.name),
        TextCellValue(account.nameAr ?? account.name),
        TextCellValue(account.nameEn ?? ''),
        TextCellValue(account.type),
        TextCellValue(account.kind.name),
        TextCellValue(account.parentId == null ? '' : byId[account.parentId]?.code ?? ''),
        TextCellValue(account.isGroup ? '1' : '0'),
        TextCellValue(account.currency),
        TextCellValue(account.supportedCurrencies.join(',')),
        DoubleCellValue(account.balance),
        TextCellValue(account.active ? '1' : '0'),
      ]);
    }
    return Uint8List.fromList(workbook.save() ?? const []);
  }
}
