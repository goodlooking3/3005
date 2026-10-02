import '../../../connectors/connector_adapter.dart';
import '../../../core/accounting.dart';
import '../../../core/connector_models.dart';
import '../../../data/accounting_repository.dart';

class BankSandboxConnector implements ConnectorAdapter {
  final AccountingRepository repository;
  final int linkedAccountId;
  ConnectorStatus _status = ConnectorStatus.disconnected;

  BankSandboxConnector({
    required this.repository,
    required this.linkedAccountId,
  });

  @override
  String get id => 'bank_sandbox';

  @override
  String get displayName => 'بنك تجريبي Sandbox';

  @override
  ConnectorStatus get status => _status;

  @override
  Future<void> connect() async {
    final accounts = await repository.accounts();
    final matches = accounts.where((item) => item.id == linkedAccountId).toList();
    final account = matches.isEmpty ? null : matches.first;
    if (account == null || account.kind != AccountKind.bank || !account.active) {
      _status = ConnectorStatus.error;
      throw StateError('الحساب البنكي المرتبط غير موجود أو غير نشط');
    }
    _status = ConnectorStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    _status = ConnectorStatus.disconnected;
  }

  @override
  Future<void> testConnection() async {
    await connect();
  }

  List<BankSandboxTransaction> get _fixture => [
        BankSandboxTransaction(
          externalId: 'SBX-20260924-001',
          amount: 1250,
          currency: 'SAR',
          direction: 'credit',
          bookedAt: DateTime.utc(2026, 9, 24, 8),
          description: 'إيداع تجريبي من عميل',
        ),
        BankSandboxTransaction(
          externalId: 'SBX-20260924-002',
          amount: 180,
          currency: 'SAR',
          direction: 'debit',
          bookedAt: DateTime.utc(2026, 9, 24, 9),
          description: 'مصروف تجريبي من الحساب البنكي',
        ),
      ];

  Future<int> syncSandbox() async {
    await connect();
    final accounts = await repository.accounts();
    final bank = accounts.firstWhere((item) => item.id == linkedAccountId);
    if (!bank.supportedCurrencies.contains('SAR')) {
      throw StateError('نسخة Sandbox الحالية تدعم الحسابات بعملة SAR فقط');
    }
    var imported = 0;
    for (final transaction in _fixture) {
      final id = await repository.importBankSandboxTransaction(
        linkedAccountId: linkedAccountId,
        transaction: transaction,
      );
      if (id != null) imported++;
    }
    return imported;
  }

  Future<int> postImported() async {
    await connect();
    final accounts = await repository.accounts();
    final bank = accounts.firstWhere((item) => item.id == linkedAccountId);
    final rows = await repository.bankSandboxTransactions();
    var posted = 0;
    for (final row in rows.where((item) => item['status'] == 'imported')) {
      final currency = row['currency']! as String;
      final counterpart = accounts.firstWhere(
        (item) =>
            item.id != bank.id &&
            item.active &&
            (item.kind == AccountKind.revenue || item.kind == AccountKind.expense) &&
            item.supportedCurrencies.contains(currency),
        orElse: () => throw StateError('لا يوجد حساب مقابل يدعم عملة $currency'),
      );
      final amount = (row['amount']! as num).toDouble();
      final direction = row['direction']! as String;
      final debit = direction == 'credit' ? bank : counterpart;
      final credit = direction == 'credit' ? counterpart : bank;
      final voucherId = await repository.insertVoucher(Voucher(
        number: 'BANK-SBX-${row['external_id']}',
        type: direction == 'credit' ? VoucherType.receipt : VoucherType.payment,
        description: row['description']! as String,
        amount: amount,
        currency: currency,
        date: DateTime.parse(row['booked_at']! as String),
        debitAccountId: debit.id,
        creditAccountId: credit.id,
        lines: [
          VoucherLine(
            accountId: debit.id,
            accountName: debit.name,
            debit: amount,
            currency: currency,
          ),
          VoucherLine(
            accountId: credit.id,
            accountName: credit.name,
            credit: amount,
            currency: currency,
          ),
        ],
      ));
      await repository.markBankSandboxPosted(
        id: row['id']! as int,
        voucherId: voucherId,
      );
      posted++;
    }
    return posted;
  }
}
