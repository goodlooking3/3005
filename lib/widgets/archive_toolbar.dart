import 'package:flutter/material.dart';

class ArchiveToolbar extends StatelessWidget {
  final String source;
  final List<String> sources;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onSourceChanged;
  final VoidCallback onAdd;

  const ArchiveToolbar({
    super.key,
    required this.source,
    required this.sources,
    required this.onQueryChanged,
    required this.onSourceChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth * .42).clamp(300, 520),
                child: TextField(
                  onChanged: onQueryChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'ابحث بالاسم أو المرجع أو الهاتف أو النص',
                  ),
                ),
              ),
              SizedBox(
                width: compact ? 170 : 190,
                child: DropdownButtonFormField<String>(
                  initialValue: source,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المصدر',
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  items: sources
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item == 'الكل' ? 'كل المصادر' : item),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onSourceChanged,
                ),
              ),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة عملية'),
              ),
            ],
          );
        },
      );
}
