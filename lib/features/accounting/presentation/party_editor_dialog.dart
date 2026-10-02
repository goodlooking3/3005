import 'package:flutter/material.dart';
import '../../../core/accounting.dart';
import '../../../data/accounting_repository.dart';

class PartyEditorDialog extends StatefulWidget {
  final AccountingRepository repository;
  const PartyEditorDialog({super.key, required this.repository});
  @override State<PartyEditorDialog> createState() => _PartyEditorDialogState();
}
class _PartyEditorDialogState extends State<PartyEditorDialog> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  String type = 'customer';
  bool saving = false;
  @override void dispose() { name.dispose(); phone.dispose(); email.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('إضافة عميل أو مورد'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
      DropdownButtonFormField<String>(value: type, decoration: const InputDecoration(labelText: 'النوع'), items: const [DropdownMenuItem(value: 'customer', child: Text('عميل')), DropdownMenuItem(value: 'supplier', child: Text('مورد'))], onChanged: saving ? null : (value) => setState(() => type = value ?? type)),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
    ])),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: saving ? null : _save, child: const Text('حفظ'))],
  );
  Future<void> _save() async {
    if (name.text.trim().isEmpty) { _message('أدخل اسم الطرف'); return; }
    setState(() => saving = true);
    try { await widget.repository.insertParty(Party(name: name.text.trim(), type: type, phone: phone.text.trim(), email: email.text.trim())); if (mounted) Navigator.pop(context, true); }
    catch (error) { if (mounted) { setState(() => saving = false); _message('تعذر حفظ الطرف: $error'); } }
  }
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
