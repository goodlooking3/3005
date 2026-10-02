import 'package:flutter/material.dart';
import '../../../core/accounting.dart';

class AccountPickerField extends StatelessWidget {
  final String label;
  final List<Account> accounts;
  final Account? value;
  final ValueChanged<Account?> onChanged;
  const AccountPickerField({super.key, required this.label, required this.accounts, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Autocomplete<Account>(
        initialValue: TextEditingValue(text: value?.name ?? ''),
        displayStringForOption: (account) => '${account.code} — ${account.name}',
        optionsBuilder: (text) {
          final query = text.text.trim().toLowerCase();
          if (query.isEmpty) return accounts;
          return accounts.where((account) => account.name.toLowerCase().contains(query) || account.code.toLowerCase().contains(query));
        },
        onSelected: onChanged,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.search)),
          onChanged: (text) {
            if (value != null && !text.contains(value!.name)) onChanged(null);
          },
        ),
      );
}

class PartyPickerField extends StatelessWidget {
  final String label;
  final List<Party> parties;
  final Party? value;
  final ValueChanged<Party?> onChanged;
  const PartyPickerField({super.key, required this.label, required this.parties, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Autocomplete<Party>(
        initialValue: TextEditingValue(text: value?.name ?? ''),
        displayStringForOption: (party) => party.name,
        optionsBuilder: (text) {
          final query = text.text.trim().toLowerCase();
          if (query.isEmpty) return parties;
          return parties.where((party) => party.name.toLowerCase().contains(query) || (party.phone ?? '').contains(query));
        },
        onSelected: onChanged,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.person_search_outlined)),
          onChanged: (text) {
            if (value != null && text != value!.name) onChanged(null);
          },
        ),
      );
}
