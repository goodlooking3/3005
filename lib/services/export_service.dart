import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import '../core/accounting.dart';
import '../core/models.dart';
import 'report_service.dart';
import '../features/my_purchases/domain/vendor_model.dart';
import '../features/my_sales/domain/inventory_item.dart';

class ExportService {
  static Future<pw.ThemeData> _arabicTheme() async {
    final regular = pw.Font.ttf(
      (await rootBundle.load('assets/Amiri-Regular.ttf')).buffer.asByteData(),
    );
    final bold = pw.Font.ttf(
      (await rootBundle.load('assets/Amiri-Bold.ttf')).buffer.asByteData(),
    );
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static Future<Uint8List> buildCreditNotePdf({
    required String invoiceNumber,
    required String customerName,
    required String currency,
    required DateTime date,
    required int journalId,
    required double total,
    required List<CreditNoteLine> lines,
  }) async {
    final document = pw.Document();
    document.addPage(pw.MultiPage(
        theme: await _arabicTheme(),
        build: (_) => [
              pw.Header(level: 0, child: pw.Text('إشعار دائن / Credit Note')),
              pw.Text('رقم الإشعار: CN-$invoiceNumber-$journalId'),
              pw.Text('الفاتورة الأصلية: $invoiceNumber'),
              pw.Text('العميل: $customerName'),
              pw.Text('التاريخ: ${date.toIso8601String()}'),
              pw.SizedBox(height: 18),
              pw.TableHelper.fromTextArray(
                headers: const ['الصنف', 'الكمية', 'سعر الوحدة', 'الإجمالي'],
                data: lines
                    .map((line) => [
                          line.itemName,
                          line.quantity.toStringAsFixed(2),
                          '${line.unitPrice.toStringAsFixed(2)} $currency',
                          '${line.total.toStringAsFixed(2)} $currency',
                        ])
                    .toList(),
              ),
              pw.SizedBox(height: 18),
              pw.Align(
                alignment: pw.AlignmentDirectional.centerEnd,
                child: pw.Text(
                    'إجمالي الإشعار: ${total.toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 24),
              pw.Text('القيد العكسي: $journalId'),
              pw.Text('تم إنشاء هذا الإشعار آليًا بعد تسجيل المرتجع.'),
            ]));
    return document.save();
  }

  static Uint8List buildExcel(List<Remittance> items) {
    final book = Excel.createExcel();
    final sheet = book['الحوالات'];
    const headers = [
      'التاريخ والوقت',
      'اسم المرسل',
      'رقم الهاتف',
      'المبلغ',
      'العملة',
      'رقم المرجع',
      'المصدر',
      'النص الكامل'
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (var row = 0; row < items.length; row++) {
      final values = [
        items[row].formattedDate,
        items[row].sender,
        items[row].phone,
        items[row].amount,
        items[row].currency,
        items[row].reference,
        items[row].source,
        items[row].message
      ];
      for (var col = 0; col < values.length; col++) {
        final value = values[col];
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
            .value = value
                is num
            ? DoubleCellValue(value.toDouble())
            : TextCellValue(value.toString());
      }
    }
    return Uint8List.fromList(book.encode() ?? <int>[]);
  }

  static Uint8List buildCommerceExcel({
    required List<PurchaseOrder> purchases,
    required List<SalesInvoice> sales,
  }) {
    final book = Excel.createExcel();
    final purchaseSheet = book['المشتريات'];
    const purchaseHeaders = [
      'الرقم',
      'المورد',
      'المحفظة',
      'الإجمالي',
      'العملة',
      'الحالة',
      'التاريخ'
    ];
    for (var i = 0; i < purchaseHeaders.length; i++) {
      purchaseSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(purchaseHeaders[i]);
    }
    for (var row = 0; row < purchases.length; row++) {
      final values = [
        purchases[row].number,
        purchases[row].vendorName,
        purchases[row].walletName,
        purchases[row].total,
        purchases[row].currency,
        purchases[row].status,
        purchases[row].createdAt.toIso8601String()
      ];
      for (var col = 0; col < values.length; col++) {
        purchaseSheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
            .value = values[col]
                is num
            ? DoubleCellValue((values[col] as num).toDouble())
            : TextCellValue(values[col].toString());
      }
    }
    final salesSheet = book['المبيعات'];
    const salesHeaders = [
      'الرقم',
      'العميل',
      'الإجمالي',
      'التكلفة',
      'الربح',
      'العملة',
      'التاريخ'
    ];
    for (var i = 0; i < salesHeaders.length; i++) {
      salesSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(salesHeaders[i]);
    }
    for (var row = 0; row < sales.length; row++) {
      final invoice = sales[row];
      final values = [
        invoice.number,
        invoice.customerName,
        invoice.total,
        invoice.costOfGoodsSold,
        invoice.profit,
        invoice.currency,
        invoice.issuedAt.toIso8601String()
      ];
      for (var col = 0; col < values.length; col++) {
        salesSheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
            .value = values[col]
                is num
            ? DoubleCellValue((values[col] as num).toDouble())
            : TextCellValue(values[col].toString());
      }
    }
    return Uint8List.fromList(book.encode() ?? <int>[]);
  }

  static Future<Uint8List> buildCommercePdf({
    required List<PurchaseOrder> purchases,
    required List<SalesInvoice> sales,
  }) async {
    final document = pw.Document();
    document.addPage(pw.MultiPage(
        theme: await _arabicTheme(),
        build: (_) => [
              pw.Text('تقرير المشتريات والمبيعات',
                  style: pw.TextStyle(fontSize: 20)),
              pw.SizedBox(height: 12),
              pw.Text('المشتريات'),
              pw.TableHelper.fromTextArray(
                  headers: const ['الرقم', 'المورد', 'الإجمالي'],
                  data: purchases
                      .map((p) =>
                          [p.number, p.vendorName, p.total.toStringAsFixed(2)])
                      .toList()),
              pw.SizedBox(height: 18),
              pw.Text('المبيعات'),
              pw.TableHelper.fromTextArray(
                  headers: const ['الرقم', 'العميل', 'الإجمالي', 'الربح'],
                  data: sales
                      .map((s) => [
                            s.number,
                            s.customerName,
                            s.total.toStringAsFixed(2),
                            s.profit.toStringAsFixed(2)
                          ])
                      .toList()),
            ]));
    return document.save();
  }

  static Uint8List buildReportExcel(
      {required List<TrialBalanceRow> trialBalance,
      required List<LedgerRow> ledger}) {
    final book = Excel.createExcel();
    final trial = book['ميزان المراجعة'];
    const headers = ['الكود', 'الحساب', 'مدين', 'دائن'];
    for (var i = 0; i < headers.length; i++) {
      trial
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (var row = 0; row < trialBalance.length; row++) {
      final item = trialBalance[row];
      final values = [item.code, item.account, item.debit, item.credit];
      for (var col = 0; col < values.length; col++) {
        trial
            .cell(
                CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
            .value = values[col]
                is num
            ? DoubleCellValue((values[col] as num).toDouble())
            : TextCellValue(values[col].toString());
      }
    }
    final ledgerSheet = book['دفتر الأستاذ'];
    const ledgerHeaders = ['التاريخ', 'الحساب', 'البيان', 'مدين', 'دائن'];
    for (var i = 0; i < ledgerHeaders.length; i++) {
      ledgerSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(ledgerHeaders[i]);
    }
    for (var row = 0; row < ledger.length; row++) {
      final item = ledger[row];
      final values = [
        item.date,
        item.account,
        item.description,
        item.debit,
        item.credit
      ];
      for (var col = 0; col < values.length; col++) {
        ledgerSheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
            .value = values[col]
                is num
            ? DoubleCellValue((values[col] as num).toDouble())
            : TextCellValue(values[col].toString());
      }
    }
    return Uint8List.fromList(book.encode() ?? <int>[]);
  }

  static Future<Uint8List> buildPdf(List<Remittance> items) async {
    final document = pw.Document();
    document.addPage(pw.Page(
        theme: await _arabicTheme(),
        build: (_) => pw.Column(children: [
              pw.Text('Wasel — Remittance Archive',
                  style: const pw.TextStyle(fontSize: 20)),
              pw.SizedBox(height: 18),
              pw.TableHelper.fromTextArray(
                  headers: const ['Date', 'Sender', 'Amount', 'Reference'],
                  data: items
                      .map((e) => [
                            e.formattedDate,
                            e.sender,
                            e.formattedAmount,
                            e.reference
                          ])
                      .toList()),
            ])));
    return document.save();
  }

  static Future<Uint8List> buildReportsPdf(
      {required String companyName,
      required List<TrialBalanceRow> trialBalance,
      required ProfitLossReport profitLoss}) async {
    final document = pw.Document();
    document.addPage(pw.MultiPage(
        theme: await _arabicTheme(),
        build: (_) => [
              pw.Header(level: 0, child: pw.Text(companyName)),
              pw.Text('التقارير المالية'),
              pw.SizedBox(height: 12),
              pw.Text('الإيرادات: ${profitLoss.revenue.toStringAsFixed(2)}'),
              pw.Text('المصروفات: ${profitLoss.expenses.toStringAsFixed(2)}'),
              pw.Text('صافي الربح: ${profitLoss.net.toStringAsFixed(2)}'),
              pw.SizedBox(height: 18),
              pw.TableHelper.fromTextArray(
                  headers: const ['الكود', 'الحساب', 'مدين', 'دائن'],
                  data: trialBalance
                      .map((r) => [
                            r.code,
                            r.account,
                            r.debit.toStringAsFixed(2),
                            r.credit.toStringAsFixed(2)
                          ])
                      .toList()),
            ]));
    return document.save();
  }

  static Future<Uint8List> buildVoucherPdf(
      {required CompanyProfile company, required Voucher voucher}) async {
    final document = pw.Document();
    document.addPage(pw.Page(
        theme: await _arabicTheme(),
        build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(company.name,
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text(company.address ?? ''),
                pw.SizedBox(height: 18),
                pw.Text(
                    voucher.type == VoucherType.receipt
                        ? 'سند قبض'
                        : voucher.type == VoucherType.payment
                            ? 'سند صرف'
                            : 'قيد يومي',
                    style: const pw.TextStyle(fontSize: 20)),
                pw.Text('رقم السند: ${voucher.number}'),
                pw.Text('التاريخ: ${voucher.date.toIso8601String()}'),
                pw.Text('البيان: ${voucher.description}'),
                pw.Text(
                    'المستلم/المستفيد: ${voucher.recipientName ?? voucher.payerName ?? ''}'),
                pw.SizedBox(height: 20),
                pw.Text(
                    'المبلغ: ${voucher.amount.toStringAsFixed(2)} ${voucher.currency}'),
                pw.SizedBox(height: 40),
                pw.Text('التوقيع: ____________________'),
              ],
            )));
    return document.save();
  }

  static Uint8List buildReportImage(
      {required ProfitLossReport profitLoss,
      required FinancialSummary summary}) {
    final canvas = img.Image(width: 1200, height: 700);
    img.fill(canvas, color: img.ColorRgb8(246, 248, 251));
    final values = [
      profitLoss.revenue,
      profitLoss.expenses,
      summary.cashBalance,
      summary.bankBalance
    ];
    final max = values.reduce((a, b) => a > b ? a : b);
    final colors = [
      img.ColorRgb8(49, 92, 255),
      img.ColorRgb8(247, 144, 9),
      img.ColorRgb8(7, 148, 85),
      img.ColorRgb8(112, 75, 160)
    ];
    for (var i = 0; i < values.length; i++) {
      final height = max <= 0 ? 0 : (values[i] / max * 500).round();
      final left = 100 + i * 260;
      img.fillRect(canvas,
          x1: left,
          y1: 600 - height,
          x2: left + 140,
          y2: 600,
          color: colors[i]);
    }
    return Uint8List.fromList(img.encodePng(canvas));
  }
}

class CreditNoteLine {
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double total;

  const CreditNoteLine({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });
}
