// Run with: flutter test tools/export_public_templates.dart
// Uses the app's own codec so downloads and static pages stay aligned with it.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/reports/domain/public_template_links.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';

void main() {
  test('export public starter structures', () {
    final directory = Directory('landing/y/templates/downloads')
      ..createSync(recursive: true);
    for (final slug in PublicTemplateLinks.ids.keys) {
      final template = PublicTemplateLinks.resolve(
        Uri.parse('https://ripot.app/?template=$slug'),
      )!;
      final payload = {
        'app': 'Ripot',
        'ripotFileType': 'template',
        'ripotExportVersion': 1,
        'template': TemplateCodec.templateToJson(template),
      };
      File(
        '${directory.path}/$slug.ripottemplate.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
    }
  });
}
