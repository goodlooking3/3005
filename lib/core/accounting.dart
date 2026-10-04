enum VoucherType { receipt, payment, journal }

enum AccountKind {
  asset,
  liability,
  equity,
  revenue,
  expense,
  cash,
  bank,
  customer,
  supplier,
}

class Account {
  final int? id;
  final String code;
  final String name;
  final String type;
  final AccountKind kind;
  final int? parentId;
  final bool isGroup;
  final String currency;
  final List<String> currencies;
  final double balance;
  final bool active;
  const Account({
    this.id,
    required this.code,
    required this.name,
    required this.type,
    this.kind = AccountKind.asset,
    this.parentId,
    this.isGroup = false,
    this.currency = 'SAR',
    this.currencies = const [],
    this.balance = 0,
    this.active = true,
  });

  List<String> get supportedCurrencies => currencies.isEmpty ? [currency] : currencies;

  Account withCurrencies(List<String> values) => Account(
        id: id,
        code: code,
        name: name,
        type: type,
        kind: kind,
        parentId: parentId,
        isGroup: isGroup,
        currency: currency,
        currencies: values,
        balance: balance,
        active: active,
      );
}

class VoucherLine {
  final int? accountId;
  final int? partyId;
  final String accountName;
  final double debit;
  final double credit;
  final String? currency;
  final String? partyName;
  const VoucherLine({
    this.accountId,
    this.partyId,
    required this.accountName,
    this.debit = 0,
    this.credit = 0,
    this.currency,
    this.partyName,
  });
  bool get isValid =>
      accountName.trim().isNotEmpty &&
      debit.isFinite &&
      credit.isFinite &&
      debit >= 0 &&
      credit >= 0 &&
      (debit == 0 || credit == 0) &&
      (debit > 0 || credit > 0);
}

class Voucher {
  final int? id;
  final String number;
  final VoucherType type;
  final String description;
  final double amount;
  final String currency;
  final DateTime date;
  final String? recipientName;
  final String? payerName;
  final int? debitAccountId;
  final int? creditAccountId;
  final List<VoucherLine> lines;
  const Voucher({
    this.id,
    required this.number,
    required this.type,
    required this.description,
    required this.amount,
    required this.currency,
    required this.date,
    this.recipientName,
    this.payerName,
    this.debitAccountId,
    this.creditAccountId,
    this.lines = const [],
  });
  bool get isBalanced =>
      lines.isEmpty ||
      lines.fold<double>(0, (sum, line) => sum + line.debit) ==
          lines.fold<double>(0, (sum, line) => sum + line.credit);
}

class Party {
  final int? id;
  final int? accountId;
  final String name;
  final String type;
  final String? phone;
  final String? email;
  final String currency;
  final bool active;
  const Party({
    this.id,
    this.accountId,
    required this.name,
    required this.type,
    this.phone,
    this.email,
    this.currency = 'SAR',
    this.active = true,
  });
}

class CompanyProfile {
  final String name;
  final String? legalName;
  final String? taxNumber;
  final String? phone;
  final String? email;
  final String? address;
  final String baseCurrency;
  const CompanyProfile({
    required this.name,
    this.legalName,
    this.taxNumber,
    this.phone,
    this.email,
    this.address,
    this.baseCurrency = 'SAR',
  });
}

class FinancialSummary {
  final double totalDebits;
  final double totalCredits;
  final int vouchersCount;
  final double cashBalance;
  final double bankBalance;
  const FinancialSummary({
    required this.totalDebits,
    required this.totalCredits,
    required this.vouchersCount,
    required this.cashBalance,
    required this.bankBalance,
  });
}

const demoAccounts = [
  Account(
    code: '1100',
    name: 'الصندوق الرئيسي',
    type: 'أصل',
    kind: AccountKind.cash,
    balance: 248650,
  ),
  Account(
    code: '1200',
    name: 'البنك — ريال سعودي',
    type: 'أصل',
    kind: AccountKind.bank,
    balance: 58200,
  ),
  Account(
    code: '4100',
    name: 'إيرادات الخدمات',
    type: 'إيراد',
    kind: AccountKind.revenue,
    balance: 12840,
  ),
  Account(
    code: '5100',
    name: 'مصروفات التشغيل',
    type: 'مصروف',
    kind: AccountKind.expense,
    balance: 3650,
  ),
];
