import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/features/accounting/presentation/account_picker_fields.dart';

void main() {
  testWidgets('selects an account by searchable code or name', (tester) async {
    Account? selected;
    const accounts = [
      Account(id: 1, code: '1100', name: 'الصندوق الرئيسي', type: 'أصل', kind: AccountKind.cash),
      Account(id: 2, code: '4100', name: 'إيرادات الخدمات', type: 'إيراد', kind: AccountKind.revenue),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountPickerField(label: 'الحساب', accounts: accounts, value: selected, onChanged: (value) => selected = value))));
    await tester.enterText(find.byType(TextField), '4100');
    await tester.pump();
    await tester.tap(find.text('4100 — إيرادات الخدمات'));
    expect(selected?.id, 2);
  });
}
