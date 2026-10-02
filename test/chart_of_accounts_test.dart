import 'package:flutter_test/flutter_test.dart';
import 'package:wasel/core/accounting.dart';
import 'package:wasel/features/accounting/presentation/account_tree.dart';

void main() {
  const root = Account(id: 1, code: '1000', name: 'الأصول', type: 'أصل', isGroup: true);
  const cash = Account(id: 2, code: '1100', name: 'الصندوق', type: 'صندوق', kind: AccountKind.cash, parentId: 1);
  const bank = Account(id: 3, code: '1200', name: 'البنك', type: 'بنك', kind: AccountKind.bank, parentId: 1);
  const inactive = Account(id: 4, code: '1300', name: 'قديم', type: 'أصل', active: false);

  test('flattens expanded account hierarchy in code order', () {
    final nodes = flattenAccountTree([bank, cash, root], expanded: {1});
    expect(nodes.map((node) => node.account.code), ['1000', '1100', '1200']);
    expect(nodes.map((node) => node.depth), [0, 1, 1]);
    expect(nodes.first.hasChildren, isTrue);
  });

  test('filters by code, name, kind, and active state', () {
    expect(filterAccounts([root, cash], query: 'الصندوق'), [cash]);
    expect(filterAccounts([root, cash], query: '1100'), [cash]);
    expect(filterAccounts([root, cash], kind: AccountKind.cash), [cash]);
    expect(filterAccounts([inactive]), isEmpty);
    expect(filterAccounts([inactive], includeInactive: true), [inactive]);
  });

  test('detects a parent cycle', () {
    final account = Account(id: 2, code: '1100', name: 'الصندوق', type: 'صندوق', parentId: 1);
    final byId = {1: root, 2: account};
    expect(accountWouldCycle(account, 1, byId), isFalse);
    expect(accountWouldCycle(account, 2, byId), isTrue);
  });
}
