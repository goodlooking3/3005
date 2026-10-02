import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/accounting/presentation/accounting_workspace_screen.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final testDirectory = Directory(
      p.join(Directory.systemTemp.path, 'wasel_accounting_interaction'),
    );
    await testDirectory.create(recursive: true);
    LocalDatabase.instance.setDatabaseDirectoryForTests(testDirectory.path);
    await LocalDatabase.instance.resetForTests();
  });

  var chartInstance = 0;

  Future<void> flushWrites(WidgetTester tester) async {
    await tester.runAsync(
      () => LocalDatabase.instance
          .waitForPendingWrites()
          .timeout(const Duration(seconds: 8)),
    );
  }

  Future<void> openChart(
      WidgetTester tester, AccountingRepository repository) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountingWorkspaceScreen(
          key: ValueKey('account-chart-${chartInstance++}'),
          repository: repository,
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    expect(find.text('دليل الحسابات'), findsOneWidget);
  }

  Future<void> seedAccount(
    WidgetTester tester,
    AccountingRepository repository,
    Account account,
  ) async {
    await tester.runAsync(() => repository.upsertAccount(account));
    await flushWrites(tester);
  }

  Future<void> enterAccount(
      WidgetTester tester, String code, String name) async {
    await tester.tap(find.text('إضافة حساب'));
    await tester.pump();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), code);
    await tester.enterText(fields.at(1), name);
    await tester.tap(find.text('حفظ الحساب'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await flushWrites(tester);
    await tester.pump();
  }

  Future<void> openAccountMenu(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField).first, code);
    await tester.pump(const Duration(milliseconds: 250));
    final title = find.textContaining('$code —');
    expect(title, findsOneWidget);
    final row = find.ancestor(of: title, matching: find.byType(ListTile));
    await tester.ensureVisible(row);
    final menu = find.descendant(
      of: row,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }

  // Keep all flows in one widget-test lifecycle: the FFI no-isolate factory
  // does not need to be torn down/re-created inside Flutter's FakeAsync zone.
  testWidgets('account chart CRUD and validation use real SQLite',
      (tester) async {
    final repository = AccountingRepository();

    // Add, persist, refresh, and search.
    await openChart(tester, repository);
    await enterAccount(tester, '1300', 'حساب الاختبار التفاعلي');
    await tester.runAsync(() async {
      expect(await repository.accountByCode('1300'), isNotNull);
    });
    await tester.tap(find.byTooltip('تحديث'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.byType(TextField).first, '1300');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('1300 —'), findsOneWidget);
    expect(find.textContaining('حساب الاختبار التفاعلي'), findsOneWidget);
    await flushWrites(tester);

    // Edit the intended row, not the first row in the scrolling table.
    await seedAccount(
      tester,
      repository,
      const Account(code: '1400', name: 'قبل التعديل', type: 'أصل'),
    );
    await openChart(tester, repository);
    await openAccountMenu(tester, '1400');
    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'بعد التعديل');
    await tester.tap(find.text('حفظ التعديل'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await flushWrites(tester);
    await tester.pump();
    await tester.runAsync(() async {
      expect((await repository.accountByCode('1400'))?.name, 'بعد التعديل');
    });

    // A leaf account can be deactivated from its own row menu.
    await seedAccount(
      tester,
      repository,
      const Account(code: '1500', name: 'حساب قابل للإيقاف', type: 'أصل'),
    );
    await openChart(tester, repository);
    await openAccountMenu(tester, '1500');
    await tester.tap(find.text('إيقاف الحساب'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await flushWrites(tester);
    await tester.pump();
    await tester.runAsync(() async {
      expect((await repository.accountByCode('1500'))?.active, isFalse);
    });

    // A parent with active children is protected from deactivation.
    await tester.runAsync(() async {
      final parent = await repository.upsertAccount(
        const Account(
          code: '1600',
          name: 'الأصل الرئيسي',
          type: 'أصل',
          isGroup: true,
        ),
      );
      await repository.upsertAccount(
        Account(
          code: '1601',
          name: 'الأصل الفرعي',
          type: 'أصل',
          parentId: parent,
        ),
      );
    });
    await flushWrites(tester);
    await openChart(tester, repository);
    await openAccountMenu(tester, '1600');
    await tester.tap(find.text('إيقاف الحساب'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await flushWrites(tester);
    await tester.pump();
    expect(find.textContaining('لا يمكن إيقاف حساب له حسابات فرعية نشطة'),
        findsOneWidget);
    await tester.runAsync(() async {
      expect((await repository.accountByCode('1600'))?.active, isTrue);
    });

    // Duplicate codes surface an actionable validation error.
    await seedAccount(
      tester,
      repository,
      const Account(code: '1700', name: 'حساب موجود', type: 'أصل'),
    );
    await openChart(tester, repository);
    await enterAccount(tester, '1700', 'محاولة تكرار');
    expect(find.textContaining('رقم الحساب مستخدم مسبقًا'), findsOneWidget);
  });
}
