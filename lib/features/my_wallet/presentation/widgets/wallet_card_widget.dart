import 'package:flutter/material.dart';

import '../../domain/models/wallet_model.dart';

class WalletCardWidget extends StatelessWidget {
  final Wallet wallet;
  final VoidCallback? onTap;
  const WalletCardWidget({super.key, required this.wallet, this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.account_balance_wallet_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        wallet.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_left_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  wallet.provider.name,
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
                const SizedBox(height: 6),
                Text(
                  wallet.accounts.isNotEmpty &&
                          wallet.accounts.every((account) => account.accountId != null && account.accountingCode != null)
                      ? 'مرتبط محاسبيًا'
                      : 'يحتاج إلى ربط محاسبي',
                  style: TextStyle(
                    color: wallet.accounts.isNotEmpty && wallet.accounts.every((account) => account.accountId != null && account.accountingCode != null)
                        ? const Color(0xFF079455)
                        : const Color(0xFFB54708),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: wallet.accounts
                      .map(
                        (account) => Chip(
                          label: Text(
                            '${account.name}: ${account.balance.toStringAsFixed(2)} ${account.currency}'
                            '${account.accountingCode == null ? '' : ' • ${account.accountingCode}'}',
                          ),
                          avatar: Icon(
                            account.connectionStatus == 'connected'
                                ? Icons.link
                                : Icons.link_off,
                            size: 16,
                          ),
                        ),
                      )
                      .toList(),
                ),
                ...wallet.accounts.map(
                  (account) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_connectionLabel(account.connectionStatus)} • ${_sourceLabel(account.balanceSource)}${account.lastSyncedAt == null ? '' : ' • ${_dateLabel(account.lastSyncedAt!)}'}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                ...wallet.accounts.where((account) => account.externalId != null).map(
                  (account) => Text(
                    'المعرف الخارجي: ${account.externalId}${account.externalType == null ? '' : ' • ${account.externalType}'}',
                    style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  String _connectionLabel(String status) => switch (status) {
        'connected' => 'متصل',
        'error' => 'خطأ في الاتصال',
        'syncing' => 'جارٍ التحديث',
        _ => 'غير متصل',
      };

  String _sourceLabel(String source) => switch (source) {
        'external' => 'رصيد من المصدر الخارجي',
        'imported' => 'رصيد مستورد',
        _ => 'رصيد يدوي',
      };

  String _dateLabel(DateTime value) => value.toLocal().toString().split('.').first;
}
