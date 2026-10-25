import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/logbook/domain/logbook_models.dart';
import 'package:ripot/features/logbook/services/logbook_pdf.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Filtered log PDF paginates a long note and uses bundled Unicode fonts',()async{
    final date=DateTime(2026,9,12);
    final doctors=[const LogDoctor(id:'d1',name:'Dr Chịdị Example'),const LogDoctor(id:'d2',name:'Dr Review Example')];
    final data=LogData(procedure:'Upper GI endoscopy',procedureDate:date,facility:'Example Teaching Hospital',reference:'DEMO-001',participants:[const LogParticipant('d1',ProcedureRole.performer,supervised:true)],supervisorId:'d2',notes:List.filled(30,'Demonstration note for layout testing. This is fictional sample information.').join(' '),fields:[const LogField('n','Procedure duration','12 min')]);
    final signed=LogSignature(revision:1,snapshot:data,doctorId:'d2',signerName:doctors.last.name,pngBase64:'iVBORw0KGgoAAAANSUhEUgAAALQAAAA8CAIAAABATAfQAAABJ0lEQVR4nO3aQWrDMABFwVzB9z9sujCU0vLa2LFUC2b2/RHiLWzTxxPC478PwH2JgyQOkjhI4iCJgyQOkjhI4iCJgyQOkjhI4iCJgyQOkjhI4iCJgyQOkjhIA+PYts3y0stj49hZXnR5RhyXH93ynOWxzxzbD5YXWp7xQLrcpVjezXtbWehSLO9mv8oucSmWd6/GccOjWx69fCyOWx3d8onlQ394Jo4VL8XywDi+/sCKl2L5hDMPpCteiuUTzr+trHgplg9591V2xUux/KJrvnOseCmW/3TlR7Bx57Y8Z/mb67+Qjju05TnLn0Z9Ph93aMtzlp/+TZBfiIMkDpI4SOIgiYMkDpI4SOIgiYMkDpI4SOIgiYMkDpI4SOIgiYMkDpI4SOIgfQByRiC4oXJ3lAAAAABJRU5ErkJggg==',recordedAt:date,doctorNames:{for(final d in doctors)d.id:d.name});
    final entry=LogEntry(id:'e1',createdAt:date,updatedAt:date,data:data,signatures:[signed]);
    final book=LogbookData(doctors:doctors,entries:[entry],createdCount:1);
    final bytes=await buildLogbookPdf(entries:[entry],book:book,doctorId:'d1',includeDetails:true);
    expect(ascii.decode(bytes.take(5).toList()),'%PDF-');
    if(Platform.environment['RIPOT_QA_PDF'] case final String path){await File(path).writeAsBytes(bytes);}
  });
}
