import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';

class ChartAccountCatalog {
  final AccountingRepository repository;
  const ChartAccountCatalog(this.repository);

  static const defaults = <Account>[
    Account(code: '1000', name: 'الأصول', type: 'أصل', kind: AccountKind.asset, isGroup: true),
    Account(code: '2000', name: 'الخصوم', type: 'التزام', kind: AccountKind.liability, isGroup: true),
    Account(code: '4000', name: 'الإيرادات', type: 'إيراد', kind: AccountKind.revenue, isGroup: true),
    Account(code: '5000', name: 'المصروفات', type: 'مصروف', kind: AccountKind.expense, isGroup: true),
  ];

  Future<List<Account>> ensureDefaults() async {
    for (final account in defaults) {
      await repository.ensureAccount(account);
    }
    return repository.accounts(includeInactive: true);
  }

  Future<Account> ensureWalletAccount({
    required String walletName,
    required String currency,
  }) async {
    final accounts = await ensureDefaults();
    final parent = accounts.firstWhere((account) => account.code == '1000');
    final existing = accounts.where(
      (account) => account.parentId == parent.id && account.name == walletName && account.currency == currency,
    );
    if (existing.isNotEmpty) return existing.first;
    final code = _nextChildCode(parent.code, accounts);
    final id = await repository.upsertAccount(Account(
      code: code,
      name: walletName,
      type: 'نقدية',
      kind: AccountKind.cash,
      parentId: parent.id,
      currency: currency,
    ));
    return (await repository.accountByCode(code))!.copyWithId(id);
  }

  String _nextChildCode(String parentCode, List<Account> accounts) {
    final used = accounts
        .map((account) => account.code)
        .where((code) => code.startsWith(parentCode))
        .map((code) => int.tryParse(code.substring(parentCode.length)) ?? 0)
        .toSet();
    var suffix = 1;
    while (used.contains(suffix)) {
      suffix++;
    }
    return '$parentCode${suffix.toString().padLeft(2, '0')}';
  }
}

extension on Account {
  Account copyWithId(int id) => Account(
        id: id,
        code: code,
        name: name,
        type: type,
        kind: kind,
        parentId: parentId,
        isGroup: isGroup,
        currency: currency,
        balance: balance,
        active: active,
      );
}
