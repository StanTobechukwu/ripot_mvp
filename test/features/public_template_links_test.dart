import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/reports/domain/public_template_links.dart';
import 'package:ripot/features/reports/providers/report_editor_provider.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('every public slug opens its exact template as a new blank report', () {
    for (final entry in PublicTemplateLinks.ids.entries) {
      final template = PublicTemplateLinks.resolve(
        Uri.parse('https://ripot-web.web.app/?template=${entry.key}'),
      )!;
      expect(template.templateId, entry.value);
      final editor = ReportEditorProvider(
        repo: ReportsRepository(),
        templatesRepo: TemplatesRepository(),
      );
      editor.newReportFromTemplate(template);
      expect(editor.doc.sourceTemplateId, entry.value);
      expect(
        editor.doc.subjectInfo.values.values.every((value) => value.isEmpty),
        isTrue,
      );
      expect(editor.doc.images, isEmpty);
      expect(editor.doc.roots, isNotEmpty);
      editor.dispose();
    }
  });
  test(
    'unknown and remote template parameters never import arbitrary content',
    () {
      expect(
        PublicTemplateLinks.resolve(Uri.parse('https://ripot-web.web.app/')),
        isNull,
      );
      expect(
        PublicTemplateLinks.resolve(
          Uri.parse(
            'https://ripot-web.web.app/?template=https://example.org/report',
          ),
        ),
        isNull,
      );
    },
  );
}
