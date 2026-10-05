import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/features/my_purchases/presentation/widgets/vendor_party_link_dialog.dart';

void main() {
  testWidgets('requires an explicit choice when supplier names are ambiguous',
      (tester) async {
    Party? selected;
    const suppliers = [
      Party(id: 11, name: 'مورد أ', type: 'supplier'),
      Party(id: 12, name: 'مورد ب', type: 'supplier'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              selected = await showVendorPartyLinkDialog(
                context: context,
                vendorName: 'متجر السوق',
                suppliers: suppliers,
              );
            },
            child: const Text('فتح الربط'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('فتح الربط'));
    await tester.pumpAndSettle();
    expect(find.text('ربط المورد المحاسبي'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ربط ومتابعة'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مورد ب').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ربط ومتابعة'));
    await tester.pumpAndSettle();
    expect(selected?.id, 12);
  });

  testWidgets('reports when no accounting suppliers exist', (tester) async {
    Party? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              selected = await showVendorPartyLinkDialog(
                context: context,
                vendorName: 'متجر السوق',
                suppliers: const [],
              );
            },
            child: const Text('فتح الربط'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('فتح الربط'));
    await tester.pumpAndSettle();
    expect(find.text('لا يوجد موردون محاسبيون'), findsOneWidget);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
