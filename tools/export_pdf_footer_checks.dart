// flutter test tools/export_pdf_footer_checks.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/letterhead_template.dart';
import 'package:ripot/features/reports/domain/pdf/pdf_plan.dart';
import 'package:ripot/features/reports/services/pdf_renderer_service.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export long free and Premium reports with images, signatures and attachments', () async {
    final output=Directory('build/pdf-footer-checks')..createSync(recursive:true);
    for (final mode in ['text','images','attachments']) {
      final images=List.generate(8,(i)=>ImageAttachment(id:'qa-$i',filePath:'test/fixtures/pdf-layout-qa.png',label:'QA IMAGE ${i+1}'));
      final doc=ReportDoc(reportId:'qa',createdAtIso:'2026-01-01',updatedAtIso:'2026-01-01',reportTitle:'FICTIONAL PRINT LAYOUT CHECK',
        fontScale:1.2,
        signature: const SignatureBlock(roleTitle:'Clinician',name:'QA SIGNATURE MARKER - NOT SIGNED',credentials:'FICTIONAL',assistantName:'QA ASSISTANT MARKER'),
        roots: List.generate(24,(i)=>SectionNode(id:'s$i',title:'QA section ${i+1}',children:[ContentNode(id:'c$i',text:List.filled(4,'Fictional layout text checks wrapping and page boundaries; this is not a clinical report.').join(' '))])),
        images:mode=='text'?const []:images);
      final plan=PdfPlan(title:doc.reportTitle,inlineEnabled:mode=='images',pageOne:PageOnePlan(inlineImages:mode=='images'?images:const []),finalContent:const FinalContentPlan(spillInlineImages:[]),attachmentPages:mode=='attachments'?[AttachmentPagePlan(images:images.take(4).toList()),AttachmentPagePlan(images:images.skip(4).toList())]:const []);
      for(final premium in [false,true]) {
        final bytes=await PdfRendererService().generatePdfBytes(doc:doc,plan:plan,showRipotBranding:!premium,
          letterhead:const LetterheadTemplate(letterheadId:'qa',name:'QA',headerLine1:'FICTIONAL QA PRINT TEST',footerLeft:'QA LETTERHEAD FOOTER',footerRight:'A4 PRINT CHECK'));
        await File('${output.path}/$mode-${premium?'premium':'free'}.pdf').writeAsBytes(bytes);
        expect(bytes.length,greaterThan(1000));
      }
    }
  });
}
