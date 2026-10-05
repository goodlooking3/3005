import 'package:flutter/material.dart';

import '../../../../core/accounting.dart';
import '../../../../data/accounting_repository.dart';
import '../../data/datasources/local_vendors_db.dart';
import '../../domain/vendor_model.dart';

Future<Vendor?> resolveVendorPartyLink(
  BuildContext context,
  Vendor vendor,
) async {
  final parties = await AccountingRepository().parties();
  final suppliers = parties
      .where((party) =>
          party.id != null && party.type == 'supplier' && party.active)
      .toList(growable: false);
  if (vendor.partyId != null &&
      suppliers.any((party) => party.id == vendor.partyId)) {
    return vendor;
  }
  final selected = await showVendorPartyLinkDialog(
    context: context,
    vendorName: vendor.name,
    suppliers: suppliers,
  );
  if (selected?.id == null) return null;
  if (vendor.id == null) {
    throw StateError('لا يمكن ربط مورد السوق قبل حفظ سجله المحلي');
  }
  await LocalVendorsDb().linkVendorToParty(
    vendorId: vendor.id!,
    partyId: selected!.id!,
  );
  return vendor.copyWith(partyId: selected.id);
}

Future<Party?> showVendorPartyLinkDialog({
  required BuildContext context,
  required String vendorName,
  required List<Party> suppliers,
}) async {
  if (suppliers.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('لا يوجد موردون محاسبيون'),
        content: const Text('أنشئ طرفاً نشطاً من نوع «مورد» ثم أعد المحاولة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    return null;
  }
  final exact = suppliers
      .where((party) =>
          party.name.trim().toLowerCase() == vendorName.trim().toLowerCase())
      .toList(growable: false);
  int? selectedId = exact.length == 1 ? exact.single.id : null;
  return showDialog<Party>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('ربط المورد المحاسبي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'اختر سجل المورد الذي يمثّل «$vendorName». لا ينشئ الربط طرفاً جديداً.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey(selectedId),
              initialValue: selectedId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المورد المسجل'),
              items: suppliers
                  .map((party) => DropdownMenuItem<int>(
                        value: party.id,
                        child: Text(
                          party.nameAr ?? party.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(growable: false),
              onChanged: (value) => setDialogState(() => selectedId = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: selectedId == null
                ? null
                : () => Navigator.pop(
                      dialogContext,
                      suppliers.singleWhere((party) => party.id == selectedId),
                    ),
            child: const Text('ربط ومتابعة'),
          ),
        ],
      ),
    ),
  );
}
