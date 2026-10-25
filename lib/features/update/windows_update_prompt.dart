import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/platform/external_url.dart';

class WindowsUpdatePrompt extends StatefulWidget {
  const WindowsUpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  State<WindowsUpdatePrompt> createState() => _WindowsUpdatePromptState();
}

class _WindowsUpdatePromptState extends State<WindowsUpdatePrompt> {
  static const _manifestUrl = 'https://ripot.app/updates/windows.json';
  bool _checkedThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checkedThisSession ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    _checkedThisSession = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final response = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || !mounted) return;

      final json = jsonDecode(response.body);
      if (json is! Map) return;
      final manifest = Map<String, dynamic>.from(json);
      if (manifest['product'] != 'Ripot' || manifest['platform'] != 'windows') {
        return;
      }

      final latestBuild = manifest['build'] is int
          ? manifest['build'] as int
          : int.tryParse(manifest['build']?.toString() ?? '') ?? 0;
      if (latestBuild <= currentBuild || !mounted) return;

      final version = (manifest['version'] ?? '').toString().trim();
      final rawUrl = (manifest['downloadUrl'] ?? '').toString().trim();
      final uri = Uri.tryParse(rawUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          !{
            'ripot.app',
            'github.com',
          }.contains(uri.host.toLowerCase())) {
        return;
      }

      final download = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ripot update available'),
          content: Text(
            version.isEmpty
                ? 'A newer Windows version of Ripot is available.'
                : 'Ripot $version is available for Windows. '
                    'Download the installer to update this installation. '
                    'Your local Ripot data stays in place.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Download update'),
            ),
          ],
        ),
      );

      if (download == true) {
        final opened = await openExternalUrl(uri.toString());
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Open ripot.app to download the Windows update.'),
            ),
          );
        }
      }
    } catch (_) {
      // Update checks must never delay or block normal Windows use.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
