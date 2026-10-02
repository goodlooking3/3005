import 'package:flutter/material.dart';

import '../../domain/models/wallet_transaction.dart';

class TransactionFiltersWidget extends StatelessWidget {
  final WalletTransactionFilter value;
  final ValueChanged<WalletTransactionFilter> onChanged;
  const TransactionFiltersWidget({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              onChanged: (text) => onChanged(
                WalletTransactionFilter(
                  type: value.type,
                  currency: value.currency,
                  status: value.status,
                  from: value.from,
                  to: value.to,
                  query: text,
                ),
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث في البيان أو الحساب',
              ),
            ),
          ),
          DropdownButton<WalletTransactionType?>(
            value: value.type,
            hint: const Text('كل الأنواع'),
            items: [
              const DropdownMenuItem(value: null, child: Text('كل الأنواع')),
              ...WalletTransactionType.values.map(
                (type) =>
                    DropdownMenuItem(value: type, child: Text(_label(type))),
              ),
            ],
            onChanged: (type) => onChanged(
              WalletTransactionFilter(
                type: type,
                currency: value.currency,
                status: value.status,
                query: value.query,
              ),
            ),
          ),
          DropdownButton<String?>(
            value: value.currency,
            hint: const Text('كل العملات'),
            items: const [
              DropdownMenuItem(value: null, child: Text('كل العملات')),
              DropdownMenuItem(value: 'SAR', child: Text('SAR')),
              DropdownMenuItem(value: 'YER', child: Text('YER')),
              DropdownMenuItem(value: 'USD', child: Text('USD')),
            ],
            onChanged: (currency) => onChanged(
              WalletTransactionFilter(
                type: value.type,
                currency: currency,
                status: value.status,
                query: value.query,
              ),
            ),
          ),
          DropdownButton<String?>(
            value: value.status,
            hint: const Text('كل الحالات'),
            items: const [
              DropdownMenuItem(value: null, child: Text('كل الحالات')),
              DropdownMenuItem(value: 'draft', child: Text('مسودة')),
              DropdownMenuItem(value: 'pending', child: Text('معلقة')),
              DropdownMenuItem(value: 'confirmed', child: Text('مؤكدة')),
              DropdownMenuItem(value: 'failed', child: Text('فاشلة')),
              DropdownMenuItem(value: 'needs_reconciliation', child: Text('تحتاج مطابقة')),
              DropdownMenuItem(value: 'posted', child: Text('مرحّلة')),
            ],
            onChanged: (status) => onChanged(
              WalletTransactionFilter(
                type: value.type,
                currency: value.currency,
                status: status,
                query: value.query,
              ),
            ),
          ),
        ],
      );

  String _label(WalletTransactionType type) => switch (type) {
        WalletTransactionType.transfer => 'تحويل',
        WalletTransactionType.receipt => 'استلام',
        WalletTransactionType.purchase => 'مشتريات',
        WalletTransactionType.billPayment => 'سداد فاتورة',
        WalletTransactionType.topUp => 'شحن حساب',
      };
}
