import '../../../core/connector_models.dart';
import '../../../core/models.dart';
import '../../../data/accounting_repository.dart';

class MessageImportService {
  final AccountingRepository repository;

  const MessageImportService(this.repository);

  Future<int> importMessage({
    required String provider,
    required String sender,
    String? senderPhone,
    required String body,
    DateTime? receivedAt,
  }) async {
    final parsed = MessageParser.parse(body);
    return repository.addIncomingMessage(
      IncomingMessage(
        provider: provider,
        sender: sender,
        senderPhone: senderPhone,
        body: body,
        receivedAt: receivedAt ?? DateTime.now(),
        parsedAmount: parsed.amount,
        parsedCurrency: parsed.currency,
        reference: parsed.reference,
      ),
    );
  }
}
