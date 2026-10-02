import '../../../../core/accounting.dart';
import '../../../../data/accounting_repository.dart';
import '../domain/inventory_item.dart';

class SalesAccountingBridge {
  final AccountingRepository accounting;
  const SalesAccountingBridge(this.accounting);

  Future<int> post(SalesInvoice invoice, {required int cashAccountId, required int salesAccountId}) async {
    if (invoice.lines.isEmpty || invoice.total <= 0) {
      throw ArgumentError('فاتورة المبيعات فارغة');
    }
    final voucherId = await accounting.insertVoucher(Voucher(
      number: invoice.number,
      type: VoucherType.receipt,
      description: 'مبيعات للعميل ${invoice.customerName}',
      amount: invoice.total,
      currency: invoice.currency,
      date: invoice.issuedAt,
      debitAccountId: cashAccountId,
      creditAccountId: salesAccountId,
      recipientName: invoice.customerName,
      lines: [
        VoucherLine(accountId: cashAccountId, accountName: invoice.paymentAccount, debit: invoice.total, partyName: invoice.customerName),
        VoucherLine(accountId: salesAccountId, accountName: 'المبيعات', credit: invoice.total),
      ],
    ));
    final journal = await accounting.journalEntries(query: invoice.number);
    return journal.firstWhere((entry) => entry.voucherId == voucherId).id;
  }
}
