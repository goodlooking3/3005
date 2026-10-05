import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/accounting/application/accounting_reports_controller.dart';
import 'package:wasel/features/accounting/presentation/accounting_reports_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async => LocalDatabase.instance.resetForTests());

  testWidgets('accounting reports render without overflow on a phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final controller = AccountingReportsController(AccountingRepository());
    await tester.pumpWidget(MaterialApp(
      home: AccountingReportsScreen(controller: controller),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('التقارير المحاسبية'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    expect(find.text('المركز المالي'), findsOneWidget);
    expect(find.text('أعمار العملاء'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  });
}
