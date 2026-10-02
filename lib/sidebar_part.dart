part of 'main.dart';

class _Sidebar extends StatelessWidget {
  final bool expanded;
  final int selected;
  final Set<int> favorites;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.expanded,
    required this.selected,
    required this.favorites,
    required this.onToggle,
    required this.onSelect,
  });

  static const _labels = [
    'نظرة عامة',
    'الحوالات والأرشيف',
    'الحسابات',
    'محفظتي',
    'مشترياتي',
    'مبيعاتي والمخزون',
    'الموصلات',
    'الإعدادات',
  ];
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.receipt_long_rounded,
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_rounded,
    Icons.shopping_bag_outlined,
    Icons.storefront_outlined,
    Icons.hub_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: expanded ? 254 : 82,
        color: WaselColors.navy,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: WaselColors.primary,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.all_inclusive_rounded,
                    color: Colors.white,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 11),
                  const Text(
                    'واصل',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 26),
            Align(
              alignment: expanded ? Alignment.centerLeft : Alignment.center,
              child: IconButton(
                onPressed: onToggle,
                tooltip: expanded ? 'طي القائمة' : 'فتح القائمة',
                icon: Icon(
                  expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
            if (expanded) ...[
              Text(
                'المفضلة',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .4),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              ...favorites.map((i) => _nav(i, _labels[i], _icons[i])),
              const SizedBox(height: 15),
              Text(
                'كل الوحدات',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .4),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
            ],
            ..._labels
                .asMap()
                .entries
                .where((e) => !favorites.contains(e.key))
                .map((item) => _nav(item.key, item.value, _icons[item.key])),
            const Spacer(),
            if (expanded)
              Text(
                'بياناتك محمية ومشفرة',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .5),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      );

  Widget _nav(int index, String label, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            decoration: BoxDecoration(
              color:
                  selected == index ? WaselColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected == index
                      ? Colors.white
                      : Colors.white.withValues(alpha: .55),
                  size: 20,
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected == index
                            ? Colors.white
                            : Colors.white.withValues(alpha: .65),
                        fontWeight: selected == index
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

