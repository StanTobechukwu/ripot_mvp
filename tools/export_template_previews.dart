// Export PDFs with the production Ripot renderer, without changing starter files.
// flutter test tools/export_template_previews.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/letterhead_template.dart';
import 'package:ripot/features/reports/domain/models/subject_info_def.dart';
import 'package:ripot/features/reports/domain/models/subject_info_value.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';
import 'package:ripot/features/reports/domain/pdf/pdf_plan.dart';
import 'package:ripot/features/reports/services/pdf_renderer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export blank forms and clearly fictional examples using the app PDF renderer', () async {
    final samples = jsonDecode(File('tools/landing/example_values.json').readAsStringSync()) as Map<String, dynamic>;
    final directory = Directory('landing/y/templates/previews')..createSync(recursive: true);
    for (final entry in samples.entries) {
      final slug = entry.key;
      final payload = jsonDecode(File('landing/y/templates/downloads/$slug.ripottemplate.json').readAsStringSync());
      final template = TemplateCodec.templateFromJson(Map<String,dynamic>.from(payload['template'] as Map));
      final values = Map<String,String>.from(entry.value as Map);
      final leafIds = <String>{};
      void collect(SectionNode n) {
        final children = n.children.whereType<SectionNode>();
        if (children.isEmpty) leafIds.add(n.id);
        for (final child in children) { collect(child); }
      }
      for (final root in template.roots) { collect(root); }
      expect(values.keys.toSet(), leafIds, reason: 'Every example field must be deliberately authored: $slug');
      for (final variant in ['blank','example']) {
        final example = variant == 'example';
        SectionNode prepare(SectionNode n) {
          final children = n.children.whereType<SectionNode>().toList();
          return n.copyWith(
            // A printable form shows conditional fields too, for handwriting.
            // Only this presentation copy changes; import/editor data is untouched.
            conditionalParentSectionId: example ? n.conditionalParentSectionId : '',
            conditionalEquals: example ? n.conditionalEquals : '',
            addToRecords: false, addToLog: false,
            unit: example && n.inputType == FieldInputType.numeric && double.tryParse(values[n.id] ?? '') == null ? '' : n.unit,
            children: children.isEmpty
                ? [ContentNode(id: '${n.id}_preview', text: example ? values[n.id]! : '____________________________')]
                : children.map(prepare).toList(),
          );
        }
        final doc = ReportDoc(
          reportId: 'preview-$slug-$variant', sourceTemplateId: template.templateId,
          createdAtIso: '2026-01-01', updatedAtIso: '2026-01-01',
          reportDateIso: example ? '2026-01-01' : '________________',
          reportTitle: template.name,
          reportLayout: ReportLayout.inline, fontScale: 1,
          roots: template.roots.map(prepare).toList(),
          subjectInfoDef: SubjectInfoBlockDef.kDefaults.copyWith(fields: [
            const SubjectFieldDef(key: 'subjectName',title:'Patient',required:true,order:0,isSystem:true,addToRecords:false),
            const SubjectFieldDef(key: 'subjectId',title:'Identifier',required:false,order:1,isSystem:true,addToRecords:false),
          ]),
          subjectInfo: SubjectInfoValues({'subjectName':example?'FICTIONAL PATIENT':'________________','subjectId':example?'DEMO-001':'________________'}),
          signature: SignatureBlock(roleTitle: 'Clinician', name: example ? 'DEMONSTRATION ONLY - NOT SIGNED' : '________________________'),
        );
        final letterhead = LetterheadTemplate(
          letterheadId:'public-preview',name:'Ripot public preview',
          headerLine1: example ? 'FICTIONAL EXAMPLE - NOT FOR CLINICAL USE' : 'BLANK REPORT TEMPLATE',
          headerLine2: example ? 'Illustrative report content only. Not a clinical reference.' : 'Complete the applicable fields for the examination performed.',
          footerLeft: example ? 'FICTIONAL EXAMPLE - NOT FOR CLINICAL USE' : 'Blank form - no prefilled clinical findings',
          footerRight: 'ripot.app',
        );
        final bytes = await PdfRendererService().generatePdfBytes(
          doc: doc,
          plan: PdfPlan(title: template.name,inlineEnabled:false,
            pageOne: const PageOnePlan(inlineImages: []),
            finalContent: const FinalContentPlan(spillInlineImages: []),attachmentPages: const []),
          letterhead: letterhead, blankReportDate: !example,
        );
        expect(latin1.decode(bytes.take(5).toList()),'%PDF-');
        await File('${directory.path}/$slug-$variant.pdf').writeAsBytes(bytes);
      }
    }
  });
}
