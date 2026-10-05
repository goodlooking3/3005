import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/connectors/application/bank_sandbox_connector.dart';
import 'package:wasel/features/connectors/application/connector_center_controller.dart';
import 'package:wasel/features/connectors/presentation/connector_center_screen.dart';

void main() {
  late Directory directory;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wasel_bank_match_');
    LocalDatabase.instance.setDatabaseDirectoryForTests(directory.path);
    await LocalDatabase.instance.resetForTests();
  });
  tearDown(() async {
    await LocalDatabase.instance.resetForTests();
    await directory.delete(recursive: true);
  });

  testWidgets('bank posting requires per-line manual matching on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = AccountingRepository();
    late int bankId;
    late ConnectorCenterController controller;
    await tester.runAsync(() async {
      bankId = await repository.upsertAccount(const Account(
        code: '1200',
        name: 'بنك المطابقة',
        type: 'أصل',
        kind: AccountKind.bank,
        currency: 'SAR',
        currencies: ['SAR'],
      ));
      await repository.upsertAccount(const Account(
        code: '4100',
        name: 'إيراد الاختبار',
        type: 'إيراد',
        kind: AccountKind.revenue,
        currency: 'SAR',
        currencies: ['SAR'],
      ));
      await repository.upsertAccount(const Account(
        code: '5100',
        name: 'مصروف الاختبار',
        type: 'مصروف',
        kind: AccountKind.expense,
        currency: 'SAR',
        currencies: ['SAR'],
      ));
      final db = await LocalDatabase.instance.database;
      await db.insert('connector_configs', {
        'provider': 'bank_sandbox',
        'display_name': 'بنك تجريبي Sandbox',
        'enabled': 1,
        'linked_account_id': bankId,
        'updated_at': DateTime.now().toIso8601String(),
      });
      await BankSandboxConnector(
        repository: repository,
        linkedAccountId: bankId,
      ).syncSandbox();
      controller = ConnectorCenterController(
        repository,
        listenToNotifications: false,
      );
      await controller.load();
    });
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConnectorCenterScreen(
          controller: controller,
          onSetup: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ترحيل محاسبي'), findsOneWidget);
    await tester.ensureVisible(find.text('ترحيل محاسبي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ترحيل محاسبي'));
    await tester.pumpAndSettle();

    expect(find.text('مطابقة كشف البنك'), findsOneWidget);
    expect(
      find.textContaining('لن يُفترض حساب إيراد أو مصروف تلقائياً'),
      findsOneWidget,
    );
    final dropdowns = find.byType(DropdownButtonFormField<int>);
    expect(dropdowns, findsNWidgets(2));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ترحيل الحركات المطابقة'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5100 · مصروف الاختبار').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4100 · إيراد الاختبار').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ترحيل الحركات المطابقة'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('مطابقة كشف البنك'), findsNothing);

    final db = await LocalDatabase.instance.database;
    expect(await db.query('vouchers'), isEmpty);
    expect(
      await db.query('bank_transactions',
          where: 'status = ?', whereArgs: ['imported']),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });
}
