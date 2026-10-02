import '../../../core/accounting.dart';

String accountKindLabel(AccountKind kind) => switch (kind) {
      AccountKind.asset => 'أصل',
      AccountKind.liability => 'التزام',
      AccountKind.equity => 'حقوق ملكية',
      AccountKind.revenue => 'إيراد',
      AccountKind.expense => 'مصروف',
      AccountKind.cash => 'صندوق',
      AccountKind.bank => 'بنك',
      AccountKind.customer => 'عميل',
      AccountKind.supplier => 'مورد',
    };

class AccountTreeNode {
  final Account account;
  final int depth;
  final bool hasChildren;
  const AccountTreeNode({required this.account, required this.depth, required this.hasChildren});
}

List<AccountTreeNode> flattenAccountTree(
  Iterable<Account> accounts, {
  Set<int> expanded = const {},
}) {
  final byParent = <int?, List<Account>>{};
  for (final account in accounts) {
    byParent.putIfAbsent(account.parentId, () => []).add(account);
  }
  for (final children in byParent.values) {
    children.sort((a, b) => a.code.compareTo(b.code));
  }
  final result = <AccountTreeNode>[];
  void visit(int? parentId, int depth) {
    for (final account in byParent[parentId] ?? const <Account>[]) {
      final hasChildren = byParent[account.id]?.isNotEmpty ?? false;
      result.add(AccountTreeNode(account: account, depth: depth, hasChildren: hasChildren));
      if (hasChildren && (account.id == null || expanded.contains(account.id))) {
        visit(account.id, depth + 1);
      }
    }
  }
  visit(null, 0);
  return result;
}

List<Account> filterAccounts(
  Iterable<Account> accounts, {
  String query = '',
  AccountKind? kind,
  bool includeInactive = false,
}) {
  final normalized = query.trim().toLowerCase();
  return accounts.where((account) {
    if (!includeInactive && !account.active) return false;
    if (kind != null && account.kind != kind) return false;
    if (normalized.isNotEmpty &&
        !account.code.toLowerCase().contains(normalized) &&
        !account.name.toLowerCase().contains(normalized)) return false;
    return true;
  }).toList(growable: false);
}

String accountStatusLabel(Account account) => account.active ? 'نشط' : 'متوقف';
String accountGroupLabel(Account account) => account.isGroup ? 'تجميعي' : 'ترحيل';
String accountIdentityLabel(Account account) => '${account.code} — ${account.name}';
String accountBalanceLabel(Account account) => '${account.balance.toStringAsFixed(2)} ${account.currency}';
String accountCodePrefix(String code) => code.length > 2 ? code.substring(0, 2) : code;

bool accountWouldCycle(Account account, int? parentId, Map<int, Account> byId) {
  var current = parentId;
  final visited = <int>{};
  while (current != null) {
    if (current == account.id || !visited.add(current)) return true;
    current = byId[current]?.parentId;
  }
  return false;
}

const accountCurrencies = ['SAR', 'USD', 'EUR', 'YER'];

String accountKindName(AccountKind kind) => accountKindLabel(kind);
String accountEditorTitle(Account? account) => account == null ? 'إضافة حساب' : 'تعديل الحساب';
String accountSaveLabel(Account? account) => account == null ? 'حفظ الحساب' : 'حفظ التعديل';
String accountSearchHint() => 'ابحث برقم الحساب أو اسمه';
String accountCountLabel(int count) => '$count حساب';
String accountEmptyMessage() => 'لا توجد حسابات مطابقة.';
