import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/features/my_wallet/data/datasources/deep_link_automation.dart';
import 'package:wasel/features/my_wallet/data/datasources/excel_pdf_importer.dart';
import 'package:wasel/features/my_wallet/data/datasources/notification_parser.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_model.dart';
import 'package:wasel/features/my_wallet/domain/models/wallet_transaction.dart';

void main() {
  const provider = WalletProviderConfig(
    id: 'provider_a',
    name: 'مزود عام',
    keywords: ['تحويل'],
    deepLink: 'provider-a://transfer',
  );

  test('notification parser extracts only configured providers', () {
    const parser = WalletNotificationParser([provider]);
    final draft = parser.parse('تحويل: تم تنفيذ 1,250 ريال، المرجع 550281');
    expect(draft?.providerId, 'provider_a');
    expect(draft?.amount, 1250);
    expect(draft?.reference, '550281');
    expect(parser.parse('رسالة عامة بلا مزود'), isNull);
  });

  test('statement exporter and importer round trip transactions', () {
    final item = WalletTransaction(
      fromAccount: 'حساب مصدر',
      toAccount: 'حساب وجهة',
      type: WalletTransactionType.transfer,
      amount: 120,
      currency: 'SAR',
      note: 'بيان عام',
      date: DateTime(2026, 1, 2),
      reference: 'R-1',
    );
    final csv = const WalletStatementImporter().exportCsv([item]);
    final result = const WalletStatementImporter().parseDelimited(csv);
    expect(result.single.amount, 120);
    expect(result.single.reference, 'R-1');
    expect(result.single.note, 'بيان عام');
  });

  test('xlsx exporter and importer round trip transactions', () {
    final item = WalletTransaction(
      fromAccount: 'حساب مصدر',
      toAccount: 'حساب وجهة',
      type: WalletTransactionType.topUp,
      amount: 75,
      currency: 'USD',
      note: 'بيان عام',
      date: DateTime(2026, 2, 3),
    );
    const importer = WalletStatementImporter();
    final result = importer.parseXlsx(importer.exportXlsx([item]));
    expect(result.single.amount, 75);
    expect(result.single.currency, 'USD');
    expect(result.single.type, WalletTransactionType.topUp);
  });

  test('deep link payload never includes authentication secrets', () {
    final payload = const DeepLinkAutomation().buildIntentPayload(
      provider: provider,
      recipient: 'رقم المستلم',
      amount: 50,
      currency: 'YER',
      note: 'بيان عام',
    );
    expect(payload, contains('recipient'));
    expect(payload, isNot(contains('pin')));
    expect(payload, isNot(contains('password')));
  });
}
