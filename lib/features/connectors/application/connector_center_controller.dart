import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/accounting.dart';
import '../../../core/connector_models.dart';
import '../../../data/accounting_repository.dart';
import '../domain/connector_item.dart';
import 'connector_catalog.dart';
import 'message_accounting_service.dart';
import 'message_import_service.dart';
import 'bank_sandbox_connector.dart';
import '../../../services/android_notification_service.dart';

class ConnectorCenterController extends ChangeNotifier {
  final AccountingRepository repository;
  final ConnectorCatalog catalog;

  ConnectorCenterController(
    this.repository, {
    this.catalog = const ConnectorCatalog(),
  }) {
    _listenToAndroidNotifications();
  }

  List<ConnectorItem> connectors = const [];
  List<IncomingMessage> messages = const [];
  List<String> accountNames = const [];
  bool loading = false;
  String? error;
  StreamSubscription<AndroidNotificationEvent>? _notificationSubscription;

  void _listenToAndroidNotifications() {
    _notificationSubscription = AndroidNotificationService().events.listen(
      (event) {
        unawaited(
          importMessage(
            provider: event.packageName,
            sender: event.title,
            body: event.body,
          ),
        );
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final saved = await repository.connectors();
      final connected = saved
          .where((item) => item.enabled)
          .map((item) => item.provider)
          .toSet();
      connectors = catalog.items
          .map(
            (item) =>
                item.copyWith(status: catalog.statusFor(item.id, connected)),
          )
          .toList();
      messages = await repository.incomingMessages();
      accountNames = (await repository.accounts())
          .map((account) => account.name)
          .toList(growable: false);
    } catch (_) {
      error = 'تعذر تحميل بيانات الموصلات والرسائل';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> archive(IncomingMessage message) async {
    if (message.id == null) return;
    await repository.archiveIncomingMessage(message.id!);
    messages =
        messages.where((item) => item.id != message.id).toList(growable: false);
    notifyListeners();
  }

  Future<void> postAndArchive(
    IncomingMessage message,
    VoucherType type,
    String debit,
    String credit,
    double amount,
    String currency,
    String description,
  ) async {
    await MessageAccountingService(repository).postMessage(
      message: message,
      type: type,
      debitAccount: debit,
      creditAccount: credit,
      amountOverride: amount,
      currencyOverride: currency,
      descriptionOverride: description,
    );
    await archive(message);
  }

  Future<void> importMessage({
    required String provider,
    required String sender,
    required String body,
    String? phone,
  }) async {
    await MessageImportService(repository).importMessage(
      provider: provider,
      sender: sender,
      body: body,
      senderPhone: phone,
    );
    messages = await repository.incomingMessages();
    notifyListeners();
  }

  Future<int> syncBankSandbox() async {
    final settings = (await repository.connectors())
        .where((item) => item.provider == 'bank_sandbox')
        .toList();
    if (settings.isEmpty || settings.first.linkedAccountId == null) {
      throw StateError('اضبط الحساب البنكي التجريبي أولًا');
    }
    final connector = BankSandboxConnector(
      repository: repository,
      linkedAccountId: settings.first.linkedAccountId!,
    );
    final count = await connector.syncSandbox();
    await load();
    return count;
  }

  Future<int> postBankSandbox() async {
    final settings = (await repository.connectors())
        .where((item) => item.provider == 'bank_sandbox')
        .toList();
    if (settings.isEmpty || settings.first.linkedAccountId == null) {
      throw StateError('اضبط الحساب البنكي التجريبي أولًا');
    }
    final connector = BankSandboxConnector(
      repository: repository,
      linkedAccountId: settings.first.linkedAccountId!,
    );
    final count = await connector.postImported();
    await load();
    return count;
  }
}
