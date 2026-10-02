import '../../domain/models/wallet_transaction.dart';

import 'package:excel/excel.dart';

class WalletStatementImporter {
  const WalletStatementImporter();

  List<WalletTransaction> parseDelimited(
    String content, {
    String separator = ',',
  }) {
    final rows = content
        .split(RegExp(r'\r?\n'))
        .where((row) => row.trim().isNotEmpty)
        .toList();
    if (rows.length < 2) return const [];
    return rows.skip(1).map((row) {
      final cells = row.split(separator).map((cell) => cell.trim()).toList();
      if (cells.length < 7) {
        throw const FormatException('صف كشف الحساب غير مكتمل');
      }
      return WalletTransaction(
        fromAccount: cells[0],
        toAccount: cells[1],
        type: WalletTransactionType.values.byName(cells[2]),
        amount: double.parse(cells[3]),
        currency: cells[4],
        note: cells[5],
        date: DateTime.parse(cells[6]),
        reference: cells.length > 7 ? cells[7] : null,
      );
    }).toList(growable: false);
  }

  String exportCsv(Iterable<WalletTransaction> transactions) {
    final buffer = StringBuffer(
      'from_account,to_account,type,amount,currency,note,date,reference\n',
    );
    for (final item in transactions) {
      buffer.writeln(
        [
          item.fromAccount,
          item.toAccount,
          item.type.name,
          item.amount,
          item.currency,
          _escape(item.note),
          item.date.toIso8601String(),
          item.reference ?? '',
        ].join(','),
      );
    }
    return buffer.toString();
  }

  List<int> exportXlsx(Iterable<WalletTransaction> transactions) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('from_account'),
      TextCellValue('to_account'),
      TextCellValue('type'),
      TextCellValue('amount'),
      TextCellValue('currency'),
      TextCellValue('note'),
      TextCellValue('date'),
      TextCellValue('reference'),
    ]);
    for (final item in transactions) {
      sheet.appendRow([
        TextCellValue(item.fromAccount),
        TextCellValue(item.toAccount),
        TextCellValue(item.type.name),
        DoubleCellValue(item.amount),
        TextCellValue(item.currency),
        TextCellValue(item.note),
        TextCellValue(item.date.toIso8601String()),
        TextCellValue(item.reference ?? ''),
      ]);
    }
    return workbook.save() ?? const [];
  }

  List<WalletTransaction> parseXlsx(List<int> bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables.values.first;
    final rows = sheet.rows;
    if (rows.length < 2) return const [];
    String value(Data? cell) => cell?.value.toString() ?? '';
    return rows
        .skip(1)
        .map(
          (row) => WalletTransaction(
            fromAccount: value(row.elementAtOrNull(0)),
            toAccount: value(row.elementAtOrNull(1)),
            type: WalletTransactionType.values.byName(
              value(row.elementAtOrNull(2)),
            ),
            amount: double.parse(value(row.elementAtOrNull(3))),
            currency: value(row.elementAtOrNull(4)),
            note: value(row.elementAtOrNull(5)),
            date: DateTime.parse(value(row.elementAtOrNull(6))),
            reference: value(row.elementAtOrNull(7)).isEmpty
                ? null
                : value(row.elementAtOrNull(7)),
          ),
        )
        .toList(growable: false);
  }

  String _escape(String value) =>
      value.contains(',') ? '"${value.replaceAll('"', '""')}"' : value;
}
