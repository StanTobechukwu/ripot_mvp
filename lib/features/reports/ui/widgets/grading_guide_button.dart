import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bundled reference content: no network call or patient data transmission.
class GradingGuideButton extends StatelessWidget {
  const GradingGuideButton({super.key, required this.role});

  final String role;
  static Map<String, dynamic>? _reference;

  static Future<Map<String, dynamic>> _load() async {
    if (_reference != null) return _reference!;
    final text = await rootBundle.loadString('assets/reference/upper_gi_gradings.json');
    // Cache the decoded content, not a Future tied to a previous async zone.
    // A failed asset load can also be retried the next time a guide is opened.
    return _reference = jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Grading guide',
        icon: const Icon(Icons.info_outline, size: 20),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => FutureBuilder<Map<String, dynamic>>(
            future: _load(),
            builder: (context, snapshot) {
              final key = role.split('.').elementAtOrNull(1);
              final guide = (snapshot.data?['guides'] as Map?)?[key] as Map?;
              return AlertDialog(
                title: Text(guide?['title'] as String? ?? 'Grading guide'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: guide == null
                        ? Text(snapshot.connectionState != ConnectionState.done
                            ? 'Loading guide…'
                            : 'This guide is unavailable. You can still enter your findings.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(guide['intro'] as String),
                              const SizedBox(height: 16),
                              for (final row in guide['rows'] as List) ...[
                                Text(row[0] as String,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(row[1] as String),
                                const SizedBox(height: 12),
                              ],
                              const Divider(),
                              Text(guide['source'] as String),
                              SelectableText(guide['url'] as String),
                              const SizedBox(height: 8),
                              Text('Updated ${snapshot.data!['updated']}'),
                            ],
                          ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              );
            },
          ),
        ),
      );
}
