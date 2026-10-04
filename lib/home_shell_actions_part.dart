part of 'main.dart';

extension _HomeShellActions on _HomeShellState {
  Future<void> _showChangePasswordDialog() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الحالية',
              ),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
              ),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'تأكيد كلمة المرور الجديدة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (next.text != confirm.text || next.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'كلمتا المرور غير متطابقتين أو أقصر من 6 أحرف',
                    ),
                  ),
                );
                return;
              }
              final ok = await AuthService().changePassword(
                currentPassword: current.text,
                newPassword: next.text,
              );
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('كلمة المرور الحالية غير صحيحة'),
                  ),
                );
                return;
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تغيير كلمة المرور')),
                );
            },
            child: const Text('حفظ التغيير'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  Future<void> _backup() async {
    try {
      final destination = await SecureBackupService.createEncryptedBackup();
      if (mounted && destination != null) {
        final action = kIsWeb
            ? 'تنزيل النسخة المشفرة'
            : 'حفظ النسخة المشفرة في';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$action $destination')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(error,
              fallback: 'تعذر إنشاء النسخة الاحتياطية. حاول مجددًا'))),
        );
      }
    }
  }

  Future<void> _restore() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wbackup'],
      withData: true,
    );
    if (result == null) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذرت قراءة ملف النسخة الاحتياطية')),
        );
      }
      return;
    }
    try {
      final count = await SecureBackupService.restoreEncryptedBackup(bytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تمت استعادة $count سجل مشفر')));
      }
      await _hydrateEntries();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(error,
              fallback: 'تعذر استعادة النسخة المشفرة. تحقق من الملف وحاول مجددًا'))),
        );
      }
    }
  }

  Future<void> _showManualRemittanceDialog() async {
    final sender = TextEditingController();
    final phone = TextEditingController();
    final amount = TextEditingController();
    final reference = TextEditingController();
    final message = TextEditingController();
    var currency = 'SAR';
    var source = 'يدوي';
    var type = EntryType.receipt;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة عملية إلى الأرشيف'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: sender,
                  decoration: const InputDecoration(labelText: 'اسم الطرف'),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                ),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'المرجع'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: const ['SAR', 'USD', 'YER']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => currency = value ?? 'SAR',
                ),
                DropdownButtonFormField<String>(
                  initialValue: source,
                  decoration: const InputDecoration(labelText: 'المصدر'),
                  items: const ['يدوي', 'WhatsApp', 'SMS', 'Messenger']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => source = value ?? 'يدوي',
                ),
                DropdownButtonFormField<EntryType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'نوع العملية'),
                  items: const [
                    DropdownMenuItem(
                      value: EntryType.receipt,
                      child: Text('مقبوضات'),
                    ),
                    DropdownMenuItem(
                      value: EntryType.expense,
                      child: Text('مصروفات'),
                    ),
                  ],
                  onChanged: (value) => type = value ?? EntryType.receipt,
                ),
                TextField(
                  controller: message,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'البيان'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final parsedAmount = double.tryParse(
                amount.text.replaceAll(',', '').trim(),
              );
              if (sender.text.trim().isEmpty ||
                  parsedAmount == null ||
                  !parsedAmount.isFinite ||
                  parsedAmount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('أدخل الطرف والمبلغ بشكل صحيح')),
                );
                return;
              }
              final item = Remittance(
                createdAt: DateTime.now(),
                sender: sender.text.trim(),
                phone: phone.text.trim(),
                amount: parsedAmount,
                currency: currency,
                reference: reference.text.trim().isEmpty
                    ? 'غير محدد'
                    : reference.text.trim(),
                message: message.text.trim().isEmpty
                    ? 'عملية مضافة يدويًا'
                    : message.text.trim(),
                source: source,
                type: type,
              );
              try {
                await LocalDatabase.instance.insert(item);
                await _hydrateEntries();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تمت إضافة العملية إلى الأرشيف'),
                    ),
                  );
                }
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(userFacingError(error,
                        fallback: 'تعذر حفظ العملية. راجع البيانات وحاول مجددًا'))),
                  );
                }
              }
            },
            child: const Text('حفظ العملية'),
          ),
        ],
      ),
    );
    sender.dispose();
    phone.dispose();
    amount.dispose();
    reference.dispose();
    message.dispose();
  }

  Future<void> _showVoucherDialog(VoucherType type) async {
    try {
      final accounts = await accounting.accounts();
      final partyType = type == VoucherType.receipt
          ? 'customer'
          : type == VoucherType.payment
          ? 'supplier'
          : null;
      final parties = await accounting.parties(type: partyType);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => VoucherEditorDialog(
          repository: accounting,
          type: type,
          accounts: accounts
              .where((item) => item.active && !item.isGroup)
              .toList(),
          parties: parties,
        ),
      );
      if (saved == true) await _hydrateAccounting();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(error,
            fallback: 'تعذر فتح نموذج السند. حاول مجددًا'))));
      }
    }
  }
}
