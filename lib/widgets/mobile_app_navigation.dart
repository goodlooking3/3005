import 'package:flutter/material.dart';

class MobileAppNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const MobileAppNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const _additionalDestinations = <(int, String, IconData)>[
    (4, 'مشترياتي', Icons.shopping_bag_outlined),
    (5, 'مبيعاتي والمخزون', Icons.storefront_outlined),
    (6, 'الإضافات والرسائل', Icons.hub_outlined),
    (7, 'الإعدادات', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: selectedIndex < 4 ? selectedIndex : 4,
        onDestinationSelected: (index) {
          if (index < 4) {
            onSelect(index);
          } else {
            _openAdditionalDestinations(context);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'الأرشيف',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_rounded),
            label: 'الحسابات',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'المحفظة',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'المزيد',
          ),
        ],
      );

  Future<void> _openAdditionalDestinations(BuildContext context) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final destination in _additionalDestinations)
              ListTile(
                leading: Icon(destination.$3),
                title: Text(destination.$2),
                selected: selectedIndex == destination.$1,
                trailing: selectedIndex == destination.$1
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, destination.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (index != null) onSelect(index);
  }
}
