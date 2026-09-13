import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/ui/item_actions.dart';
import '../../../core/utils/ids.dart';
import '../data/logbook_repository.dart';
import '../domain/logbook_models.dart';

String doctorLabel(LogDoctor d) =>
    d.detail.isEmpty ? d.name : '${d.name} · ${d.detail}';

Future<LogDoctor?> editDoctor(BuildContext context, {LogDoctor? doctor}) async {
  final repo = context.read<LogbookRepository>();
  var name = doctor?.name ?? '';
  var detail = doctor?.detail ?? '';
  var isMe = doctor != null
      ? repo.data.meId == doctor.id
      : repo.data.meId.isEmpty;
  final form = GlobalKey<FormState>();
  final values = await showDialog<(String, String, bool)>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, change) => AlertDialog(
        title: Text(doctor == null ? 'Add doctor' : 'Edit doctor'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  maxLength: 200,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (v) => name = v,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name' : null,
                ),
                TextFormField(
                  initialValue: detail,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Department or distinguishing detail (optional)',
                  ),
                  onChanged: (v) => detail = v,
                  validator: (v) {
                    final duplicate = repo.data.doctors.any(
                      (d) =>
                          d.id != doctor?.id &&
                          d.name.toLowerCase() == name.trim().toLowerCase() &&
                          d.detail.toLowerCase() ==
                              (v ?? '').trim().toLowerCase(),
                    );
                    return duplicate
                        ? 'Use a different detail for people with identical names'
                        : null;
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('This is me'),
                  value: isMe,
                  onChanged: (v) => change(() => isMe = v ?? false),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialog, (name.trim(), detail.trim(), isMe));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (values == null) return null;
  final next = LogDoctor(
    id: doctor?.id ?? newId('doctor'),
    name: values.$1,
    detail: values.$2,
  );
  try {
    await repo.saveDoctor(next, isMe: values.$3);
    return next;
  } catch (_) {
    if (context.mounted) {
      showMessage(context, 'Could not save doctor. Please try again.');
    }
    return null;
  }
}

Future<LogDoctor?> pickDoctor(
  BuildContext context, {
  String title = 'Choose doctor',
}) async {
  final repo = context.read<LogbookRepository>();
  final doctors = [...repo.data.doctors]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final selected = await showItemActions(context, title, [
    for (final d in doctors)
      ItemAction(
        d.id,
        '${doctorLabel(d)}${d.id == repo.data.meId ? ' (me)' : ''}',
        Icons.person_outline,
      ),
    const ItemAction('add', 'Add doctor', Icons.person_add_alt),
  ]);
  if (selected == null || !context.mounted) return null;
  if (selected == 'add') return editDoctor(context);
  return repo.data.doctor(selected);
}

class DoctorDirectoryScreen extends StatelessWidget {
  const DoctorDirectoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LogbookRepository>();
    final doctors = [...repo.data.doctors]
      ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Doctors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editDoctor(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add doctor'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Choose “This is me” to prefill your Quick Logs. Other participants are optional. Renaming a doctor keeps their logs together.',
              ),
            ),
            for (final d in doctors)
              Card(
                child: ListTile(
                  title: Text(doctorLabel(d)),
                  subtitle: d.id == repo.data.meId ? const Text('Me') : null,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => editDoctor(context, doctor: d),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
