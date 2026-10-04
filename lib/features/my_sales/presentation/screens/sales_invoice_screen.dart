import 'package:flutter/material.dart';

import '../../../../data/accounting_repository.dart';
import '../../../../data/currency_repository.dart';
import '../../../../core/accounting.dart';
import '../../data/datasources/inventory_local_db.dart';
import '../../data/sales_engine.dart';
import '../../domain/inventory_item.dart';

class SalesInvoiceScreen extends StatefulWidget {
  const SalesInvoiceScreen({super.key});

  @override
  State<SalesInvoiceScreen> createState() => _SalesInvoiceScreenState();
}

class _SalesInvoiceScreenState extends State<SalesInvoiceScreen> {
  final inventory = InventoryLocalDb();
  final accounting = AccountingRepository();
  final currencies = CurrencyRepository();
  final search = TextEditingController();
  final customer = TextEditingController(text: 'عميل نقدي');
  List<InventoryItem> items = [];
  List<Account> accounts = [];
  List<Party> parties = [];
  List<CurrencyOption> currencyOptions = [];
  final quantities = <int, double>{};
  String currency = 'SAR';
  int? cashAccountId;
  int? salesAccountId;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
    search.addListener(() => setState(() {}));
    customer.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    search.dispose();
    customer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final loadedItems = await inventory.items();
      final loadedAccounts = await accounting.accounts();
      final loadedParties = await accounting.parties();
      final loadedCurrencies = await currencies.activeCurrencies();
      if (!mounted) return;
      setState(() {
        items = loadedItems;
        accounts = loadedAccounts;
        parties = loadedParties;
        currencyOptions = loadedCurrencies;
        cashAccountId = _firstAccount(AccountKind.cash, AccountKind.bank)?.id;
        salesAccountId = _firstAccount(AccountKind.revenue)?.id;
        loading = false;
      });
    } catch (value) {
      if (mounted)
        setState(() {
          error = 'تعذر تحميل بيانات فاتورة البيع. اضغط تحديث وحاول مجددًا';
          loading = false;
        });
    }
  }

  Account? _firstAccount(AccountKind first, [AccountKind? second]) {
    for (final account in accounts) {
      if (account.kind == first || (second != null && account.kind == second)) {
        return account;
      }
    }
    return null;
  }

  List<InventoryItem> get filteredItems {
    final term = search.text.trim().toLowerCase();
    return items.where((item) {
      final sameCurrency = item.currency.trim().toUpperCase() == currency;
      final matchesSearch = term.isEmpty ||
          item.name.toLowerCase().contains(term) ||
          item.sku.toLowerCase().contains(term);
      return sameCurrency && matchesSearch;
    }).toList();
  }
  double get cartTotal => cart.fold<double>(
      0, (total, item) => total + _quantity(item) * item.salePrice);
  void _setCurrency(String value) {
    setState(() {
      currency = value;
      if (!_accountSupportsCurrency(cashAccountId, currency)) {
        cashAccountId = null;
      }
      if (!_accountSupportsCurrency(salesAccountId, currency)) {
        salesAccountId = null;
      }
      quantities.removeWhere((id, _) {
        final matches = items.where((candidate) => candidate.id == id);
        final item = matches.isEmpty ? null : matches.first;
        return item != null && item.currency.trim().toUpperCase() != currency;
      });
    });
  }

  bool _accountSupportsCurrency(int? accountId, String value) {
    if (accountId == null) return false;
    for (final account in accounts) {
      if (account.id == accountId) {
        return account.supportedCurrencies.contains(value);
      }
    }
    return false;
  }

  List<InventoryItem> get cart =>
      items.where((item) => quantities.containsKey(item.id)).toList();

  List<Party> get matchingParties {
    final term = customer.text.trim().toLowerCase();
    if (term.isEmpty) return const [];
    return parties
        .where((party) => party.name.toLowerCase().contains(term))
        .take(5)
        .toList(growable: false);
  }

  double _quantity(InventoryItem item) => quantities[item.id] ?? 0;

  void _add(InventoryItem item) {
    if (item.id == null || _quantity(item) >= item.quantity) return;
    setState(() => quantities[item.id!] = _quantity(item) + 1);
  }

  void _remove(InventoryItem item) {
    if (item.id == null) return;
    final next = _quantity(item) - 1;
    setState(() =>
        next <= 0 ? quantities.remove(item.id) : quantities[item.id!] = next);
  }

  Future<void> _post() async {
    if (customer.text.trim().isEmpty ||
        cart.isEmpty ||
        cashAccountId == null ||
        salesAccountId == null) {
      setState(
          () => error = 'أكمل العميل والمنتجات وحساب التحصيل وحساب المبيعات');
      return;
    }
    final lines = cart
        .map((item) => SalesInvoiceLine(
              itemId: item.id!,
              itemName: item.name,
              quantity: _quantity(item),
              unitPrice: item.salePrice,
              unitCost: item.costPrice,
            ))
        .toList();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await SalesEngine().completeSale(
        invoice: SalesInvoice(
          number: 'SALE-${DateTime.now().millisecondsSinceEpoch}',
          customerName: customer.text.trim(),
          paymentAccount:
              accounts.firstWhere((a) => a.id == cashAccountId).name,
          currency: currency,
          issuedAt: DateTime.now(),
          lines: lines,
        ),
        cashAccountId: cashAccountId!,
        salesAccountId: salesAccountId!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          error = 'تعذر ترحيل الفاتورة. تحقق من الحساب والعملة والكمية ثم حاول مجددًا';
          loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && (loading || error != null))
      return Scaffold(
        body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
        ),
      );
    final cashAccounts = accounts
        .where((a) =>
            (a.kind == AccountKind.cash || a.kind == AccountKind.bank) &&
            a.supportedCurrencies.contains(currency))
        .toList();
    final revenueAccounts =
        accounts
            .where((a) =>
                a.kind == AccountKind.revenue &&
                a.supportedCurrencies.contains(currency))
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة بيع جديدة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null)
          Card(
              color: Colors.red.shade50,
              child: Padding(
                  padding: const EdgeInsets.all(12), child: Text(error!))),
        TextField(
            controller: customer,
            decoration: const InputDecoration(labelText: 'العميل')),
        ...matchingParties.map((party) => ListTile(
              dense: true,
              leading: const Icon(Icons.person_search),
              title: Text(party.name),
              subtitle: Text(party.type),
              onTap: () => setState(() => customer.text = party.name),
            )),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final fields = [
            DropdownButtonFormField<String>(
                  value: currency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: (currencyOptions.isEmpty
                          ? [
                              const CurrencyOption(
                                  code: 'SAR',
                                  name: 'ريال سعودي',
                                  symbol: 'ر.س')
                            ]
                          : currencyOptions)
                      .map((item) => DropdownMenuItem(
                          value: item.code,
                          child: Text('${item.code} — ${item.name}')))
                      .toList(),
                  onChanged: (value) => _setCurrency(value ?? 'SAR')),
            DropdownButtonFormField<int>(
                value: cashAccountId,
                decoration: const InputDecoration(labelText: 'حساب التحصيل'),
                items: cashAccounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (value) => setState(() => cashAccountId = value)),
          ];
          return compact
              ? Column(children: [fields[0], const SizedBox(height: 8), fields[1]])
              : Row(children: [Expanded(child: fields[0]), const SizedBox(width: 8), Expanded(child: fields[1])]);
        }),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
            value: salesAccountId,
            decoration: const InputDecoration(labelText: 'حساب المبيعات'),
            items: revenueAccounts
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (value) => setState(() => salesAccountId = value)),
        const SizedBox(height: 16),
        TextField(
            controller: search,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'ابحث عن صنف أو SKU')),
        ...filteredItems.map((item) => ListTile(
            title: Text(item.name),
            subtitle:
                Text('${item.sku} — متاح ${item.quantity} ${item.currency}'),
            trailing: IconButton(
                onPressed: () => _add(item),
                icon: const Icon(Icons.add_shopping_cart)))),
        const Divider(),
        const Text('بنود الفاتورة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...cart.map((item) => ListTile(
            title: Text(item.name),
            subtitle: Text(
                '${(_quantity(item) * item.salePrice).toStringAsFixed(2)} $currency'),
            leading: IconButton(
                onPressed: () => _remove(item),
                icon: const Icon(Icons.remove_circle_outline)),
            trailing: Text(_quantity(item).toStringAsFixed(0)))),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('إجمالي الفاتورة'),
            trailing: Text('${cartTotal.toStringAsFixed(2)} $currency', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        FilledButton.icon(
            onPressed: loading ? null : _post,
            icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.receipt_long),
            label: Text(loading ? 'جارٍ الترحيل...' : 'ترحيل الفاتورة')),
      ]),
    );
  }
}
