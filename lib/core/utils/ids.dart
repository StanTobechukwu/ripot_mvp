import 'dart:math';

String newId(String prefix) {
  final r = Random();
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(999999)}';
}
