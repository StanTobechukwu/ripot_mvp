// Fictional clipboard integration fixture. Built separately from the shipped app.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/subject_info_value.dart';
import 'package:ripot/features/reports/services/report_copy_service.dart';
import 'package:ripot/features/reports/ui/report_copy_action.dart';

SemanticsHandle? semantics;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  semantics = SemanticsBinding.instance.ensureSemantics();
  final copied = <String>{};
  final service = ReportCopyService(currentUid: () => 'fictional-copy-test',
    call: (name, data) async {
      var charged = false;
      if (name == 'authorizeReportCopy') {
        charged = copied.add(data['fingerprint'] as String);
      }
      return {'limit': 50, 'remaining': 50 - copied.length,
        'unlimited': false, 'repeated': name == 'authorizeReportCopy' && !charged,
        'charged': charged};
    });
  const doc = ReportDoc(reportId: 'clipboard-qa', createdAtIso: '2026-11-02',
    updatedAtIso: '2026-11-02', reportTitle: 'Fictional clinical report',
    reportLayout: ReportLayout.aligned,
    subjectInfo: SubjectInfoValues({'subjectName': 'Fictional Patient', 'subjectId': 'TEST-001'}),
    roots: [SectionNode(id: 'findings', title: 'Findings', children: [
      ContentNode(id: 'first', text: 'First full paragraph.'),
      ContentNode(id: 'second', text: 'Second full paragraph.\nAnother line.'),
      SectionNode(id: 'measurement', title: 'Measurement', unit: 'mm', inputType: FieldInputType.numeric,
        children: [ContentNode(id: 'value', text: '12.5')]),
      SectionNode(id: 'internal', title: 'Internal', showInPdf: false,
        children: [ContentNode(id: 'secret', text: 'NOT FOR CLIPBOARD')]),
    ])]);
  runApp(MaterialApp(theme: ThemeData(colorSchemeSeed: const Color(0xff00695e)),
    home: Scaffold(appBar: AppBar(title: const Text('Copy report — fictional test')),
      body: ReportCopyAction(doc: doc, accountUid: 'fictional-copy-test',
        access: AccessState.initial(installationId: 'fictional-test'), service: service,
        onSignIn: () async {}, onUpgrade: () async {}))));
}
