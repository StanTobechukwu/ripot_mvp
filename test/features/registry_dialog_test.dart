import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/registry/ui/registry_screen.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/domain/record_models.dart';

void main() {
  testWidgets('rename registry and patient keeps patient identity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = RecordsRepository();
    final registry = await repo.createRegistry(title: 'Clinic');
    final patients = RegistryRepository();
    final patient = await patients.addPatient(
      name: 'Old name',
      reference: '123',
      registryId: registry.registryId,
    );
    await tester.pumpWidget(
      Provider.value(
        value: repo,
        child: MaterialApp(home: RegistryPatientsScreen(registry: registry)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Registry options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename registry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Renamed clinic');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed clinic'), findsOneWidget);
    await tester.tap(find.text('Old name'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit patient name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'New name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('New name')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('New name')),
      findsOneWidget,
    );
    final data = await patients.load();
    expect(data.patients.single.name, 'New name');
    expect(data.patients.single.id, patient.id);
    expect(data.patients.single.reference, '123');
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty update can configure fields and return to entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = RecordsRepository();
    final registry = await repo.createRegistry(title: 'Clinic');
    final patient = await RegistryRepository().addPatient(
      name: 'Patient',
      registryId: registry.registryId,
    );
    await tester.pumpWidget(
      Provider.value(
        value: repo,
        child: MaterialApp(
          home: RegistryUpdateScreen(registry: registry, patient: patient),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save update'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Add fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Field name'),
      'Haemoglobin',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Haemoglobin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fields with the same group appear in one group card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = RecordsRepository();
    final created = await repo.createRegistry(title: 'Clinic');
    await repo.saveRegistryFields(created.registryId, const [
      RecordFieldDef(
        key: 'ft3',
        label: 'FT3',
        hint: '',
        groupName: 'Thyroid function tests',
      ),
      RecordFieldDef(
        key: 'tsh',
        label: 'TSH',
        hint: '',
        groupName: 'Thyroid function tests',
      ),
    ]);
    final registry = (await repo.loadRegistries()).single;
    await tester.pumpWidget(
      Provider.value(
        value: repo,
        child: MaterialApp(home: RegistryFieldsScreen(registry: registry)),
      ),
    );
    expect(find.text('Thyroid function tests'), findsOneWidget);
    expect(find.text('FT3'), findsOneWidget);
    expect(find.text('TSH'), findsOneWidget);
    expect(find.text('Add full blood count'), findsNothing);
  });
  testWidgets('field type switching, saving and cancelling are safe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = RecordsRepository();
    final registry = await repo.createRegistry(title: 'Clinic');
    await tester.pumpWidget(
      Provider.value(
        value: repo,
        child: MaterialApp(home: RegistryFieldsScreen(registry: registry)),
      ),
    );
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Field name'),
      'Diagnosis',
    );
    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multiple choices').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Choices, one per line'),
      'One\nTwo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Field name'),
      'Findings',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Findings'), findsOneWidget);
    await tester.tap(find.text('Findings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
