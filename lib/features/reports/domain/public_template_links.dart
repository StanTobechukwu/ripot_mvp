import '../data/built_in_templates.dart';
import 'models/template_doc.dart';

/// Public URLs resolve only to bundled, patient-free starter templates.
/// No arbitrary URL fetches, report imports or replacement of personal templates.
class PublicTemplateLinks {
  static const ids = <String, String>{
    'upper-gi-endoscopy-report-template': BuiltInTemplates.upperGiId,
    'colonoscopy-report-template': BuiltInTemplates.lowerGiId,
    'abdominal-ultrasound-report-template': BuiltInTemplates.ultrasoundId,
    'echocardiogram-report-template': BuiltInTemplates.echoId,
  };

  static TemplateDoc? resolve(Uri uri) {
    final slug = uri.queryParameters['template'];
    final id = ids[slug];
    if (id == null) return null;
    return BuiltInTemplates.all().firstWhere(
      (template) => template.templateId == id,
    );
  }
}
