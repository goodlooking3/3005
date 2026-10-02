import '../../../core/accounting.dart';
import '../../../core/connector_models.dart';
import '../../../data/accounting_repository.dart';

class MessageAccountingService {
  final AccountingRepository repository;

  const MessageAccountingService(this.repository);

  Future<int> postMessage({
    required IncomingMessage message,
    required VoucherType type,
    required String debitAccount,
    required String creditAccount,
    double? amountOverride,
    String? currencyOverride,
    String? descriptionOverride,
  }) async {
    final amount = amountOverride ?? message.parsedAmount;
    if (amount == null || amount <= 0) {
      throw ArgumentError('لا يمكن ترحيل رسالة بلا مبلغ صالح');
    }

    final debitId = await repository.accountIdByName(debitAccount);
    final creditId = await repository.accountIdByName(creditAccount);
    if (debitId == null || creditId == null || debitId == creditId) {
      throw StateError('الحساب المدين أو الدائن غير موجود أو متماثل');
    }
    final reference = message.reference?.trim();
    final number = reference == null || reference.isEmpty
        ? 'MSG-${DateTime.now().millisecondsSinceEpoch}'
        : 'MSG-$reference';
    final description = descriptionOverride?.trim().isNotEmpty == true
        ? descriptionOverride!.trim()
        : 'ترحيل رسالة ${message.provider} من ${message.sender}';

    return repository.insertVoucher(
      Voucher(
        number: number,
        type: type,
        description: description,
        amount: amount,
        currency: currencyOverride?.trim().isNotEmpty == true
            ? currencyOverride!.trim()
            : message.parsedCurrency ?? 'SAR',
        date: message.receivedAt,
        recipientName: type == VoucherType.receipt ? message.sender : null,
        payerName: type == VoucherType.payment ? message.sender : null,
        lines: [
          VoucherLine(
            accountId: debitId,
            accountName: debitAccount,
            debit: amount,
            partyName: message.sender,
          ),
          VoucherLine(
            accountId: creditId,
            accountName: creditAccount,
            credit: amount,
            partyName: message.sender,
          ),
        ],
      ),
    );
  }
}
