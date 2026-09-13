import 'package:flutter/material.dart';

class ItemAction {
  final String id;
  final String label;
  final IconData icon;
  final bool destructive;
  const ItemAction(this.id, this.label, this.icon, {this.destructive = false});
}

Future<String?> showItemActions(
  BuildContext context,
  String title,
  List<ItemAction> actions,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheet).height * .8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(title, style: Theme.of(sheet).textTheme.titleLarge),
            ),
            for (final action in actions) ...[
              if (action.destructive) const Divider(),
              ListTile(
                leading: Icon(
                  action.icon,
                  color: action.destructive
                      ? Theme.of(sheet).colorScheme.error
                      : null,
                ),
                title: Text(
                  action.label,
                  style: TextStyle(
                    color: action.destructive
                        ? Theme.of(sheet).colorScheme.error
                        : null,
                  ),
                ),
                onTap: () => Navigator.pop(sheet, action.id),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  ),
);

Future<String?> askName(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  var value = initial;
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (v) => value = v,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Enter a name' : null,
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
              Navigator.pop(dialog, value.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message, {
  String action = 'Delete',
  bool destructive = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialog).colorScheme.error,
                    foregroundColor: Theme.of(dialog).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void showMessage(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

String readableDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
