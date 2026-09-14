import 'dart:convert';

String formatReportIdForDisplay(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  if (value.startsWith('RPT-')) return value;
  final suffix = value.length <= 6 ? value : value.substring(value.length - 6);
  return 'RPT-$suffix';
}

enum RecordInputType { freeText, yesNo, singleSelect, multiSelect, numeric }

class RecordFieldDef {
  final String key;
  final String label;
  final String hint;
  final List<String> builtInSuggestions;
  final bool isSystem;
  final String procedureScope;
  final String registryId;
  final String conditionalOnFieldKey;
  final String conditionalEquals;
  final RecordInputType inputType;
  final List<String> options;
  final String unit;
  final String groupName;

  const RecordFieldDef({
    required this.key,
    required this.label,
    required this.hint,
    this.builtInSuggestions = const [],
    this.isSystem = true,
    this.procedureScope = '',
    this.registryId = '',
    this.conditionalOnFieldKey = '',
    this.conditionalEquals = '',
    this.inputType = RecordInputType.freeText,
    this.options = const <String>[],
    this.unit = '',
    this.groupName = '',
  });

  RecordFieldDef copyWith({
    String? key,
    String? label,
    String? hint,
    List<String>? builtInSuggestions,
    bool? isSystem,
    String? procedureScope,
    String? registryId,
    String? conditionalOnFieldKey,
    String? conditionalEquals,
    RecordInputType? inputType,
    List<String>? options,
    String? unit,
    String? groupName,
  }) {
    return RecordFieldDef(
      key: key ?? this.key,
      label: label ?? this.label,
      hint: hint ?? this.hint,
      builtInSuggestions: builtInSuggestions ?? this.builtInSuggestions,
      isSystem: isSystem ?? this.isSystem,
      procedureScope: procedureScope ?? this.procedureScope,
      registryId: registryId ?? this.registryId,
      conditionalOnFieldKey:
          conditionalOnFieldKey ?? this.conditionalOnFieldKey,
      conditionalEquals: conditionalEquals ?? this.conditionalEquals,
      inputType: inputType ?? this.inputType,
      options: options ?? this.options,
      unit: unit ?? this.unit,
      groupName: groupName ?? this.groupName,
    );
  }

  bool get isGlobal =>
      procedureScope.trim().isEmpty && registryId.trim().isEmpty;
  bool get isRegistryField => registryId.trim().isNotEmpty;

  bool appliesToProcedure(String procedureName) {
    if (isRegistryField) return true;
    if (isGlobal) return true;
    return procedureScope.trim().toLowerCase() ==
        procedureName.trim().toLowerCase();
  }

  bool appliesToRegistries(Iterable<String> registryIds) {
    if (!isRegistryField) return true;
    return registryIds.map((e) => e.trim()).contains(registryId.trim());
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'hint': hint,
    'builtInSuggestions': builtInSuggestions,
    'isSystem': isSystem,
    'procedureScope': procedureScope,
    'registryId': registryId,
    'conditionalOnFieldKey': conditionalOnFieldKey,
    'conditionalEquals': conditionalEquals,
    'inputType': inputType.name,
    'options': options,
    'unit': unit,
    'groupName': groupName,
  };

  factory RecordFieldDef.fromJson(Map<String, dynamic> json) {
    final suggestions =
        (json['builtInSuggestions'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const <String>[];
    final inputTypeName = (json['inputType'] ?? '').toString();
    final inputType = RecordInputType.values.firstWhere(
      (value) => value.name == inputTypeName,
      orElse: () => RecordInputType.freeText,
    );
    final options =
        (json['options'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    return RecordFieldDef(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      hint: (json['hint'] ?? '').toString(),
      builtInSuggestions: suggestions,
      isSystem: (json['isSystem'] ?? false) == true,
      procedureScope: (json['procedureScope'] ?? '').toString(),
      registryId: (json['registryId'] ?? '').toString(),
      conditionalOnFieldKey: (json['conditionalOnFieldKey'] ?? '').toString(),
      conditionalEquals: (json['conditionalEquals'] ?? '').toString(),
      inputType: inputType,
      options: options,
      unit: (json['unit'] ?? '').toString(),
      groupName: (json['groupName'] ?? '').toString(),
    );
  }
}

class RecordRegistry {
  final String registryId;
  final String title;
  final String description;
  final String createdAtIso;
  final List<RecordFieldDef> fields;

  const RecordRegistry({
    required this.registryId,
    required this.title,
    this.description = '',
    required this.createdAtIso,
    this.fields = const <RecordFieldDef>[],
  });

  RecordRegistry copyWith({
    String? registryId,
    String? title,
    String? description,
    String? createdAtIso,
    List<RecordFieldDef>? fields,
  }) {
    return RecordRegistry(
      registryId: registryId ?? this.registryId,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() => {
    'registryId': registryId,
    'title': title,
    'description': description,
    'createdAtIso': createdAtIso,
    'fields': fields.map((e) => e.toJson()).toList(growable: false),
  };

  factory RecordRegistry.fromJson(Map<String, dynamic> json) {
    final rawFields = (json['fields'] as List?) ?? const <dynamic>[];
    return RecordRegistry(
      registryId: (json['registryId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      createdAtIso: (json['createdAtIso'] ?? '').toString(),
      fields: rawFields
          .map(
            (e) => RecordFieldDef.fromJson((e as Map).cast<String, dynamic>()),
          )
          .where((field) => field.key.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}

class RecordEntry {
  final Map<String, String> originalReportValues;
  final String recordEntryId;
  final String linkedReportId;
  final String createdAtIso;
  final String updatedAtIso;
  final Map<String, String> values;
  final Map<String, String> fieldLabels;
  final Map<String, String> fieldSources;
  final List<String> registryIds;
  final Map<String, RecordFieldDef> fieldDefinitions;

  const RecordEntry({
    this.originalReportValues = const {},
    required this.recordEntryId,
    required this.linkedReportId,
    required this.createdAtIso,
    required this.updatedAtIso,
    required this.values,
    this.fieldLabels = const <String, String>{},
    this.fieldSources = const <String, String>{},
    this.registryIds = const <String>[],
    this.fieldDefinitions = const <String, RecordFieldDef>{},
  });

  String valueOf(String key) => values[key]?.trim() ?? '';

  RecordEntry copyWith({
    Map<String, String>? originalReportValues,
    String? recordEntryId,
    String? linkedReportId,
    String? createdAtIso,
    String? updatedAtIso,
    Map<String, String>? values,
    Map<String, String>? fieldLabels,
    Map<String, String>? fieldSources,
    List<String>? registryIds,
    Map<String, RecordFieldDef>? fieldDefinitions,
  }) {
    return RecordEntry(
      originalReportValues: originalReportValues ?? this.originalReportValues,
      recordEntryId: recordEntryId ?? this.recordEntryId,
      linkedReportId: linkedReportId ?? this.linkedReportId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      values: values ?? this.values,
      fieldLabels: fieldLabels ?? this.fieldLabels,
      fieldSources: fieldSources ?? this.fieldSources,
      registryIds: registryIds ?? this.registryIds,
      fieldDefinitions: fieldDefinitions ?? this.fieldDefinitions,
    );
  }

  Map<String, dynamic> toJson() => {
    'recordEntryId': recordEntryId,
    'originalReportValues': originalReportValues,
    'linkedReportId': linkedReportId,
    'createdAtIso': createdAtIso,
    'updatedAtIso': updatedAtIso,
    'values': values,
    'fieldLabels': fieldLabels,
    'fieldSources': fieldSources,
    'registryIds': registryIds,
    'fieldDefinitions': fieldDefinitions.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory RecordEntry.fromJson(Map<String, dynamic> json) {
    final rawValues =
        (json['values'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rawLabels =
        (json['fieldLabels'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rawSources =
        (json['fieldSources'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final registries =
        (json['registryIds'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final rawDefinitions =
        (json['fieldDefinitions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return RecordEntry(
      recordEntryId: (json['recordEntryId'] ?? '') as String,
      originalReportValues: Map<String, String>.from(
        json['originalReportValues'] as Map? ?? {},
      ),
      linkedReportId: (json['linkedReportId'] ?? '') as String,
      createdAtIso: (json['createdAtIso'] ?? '') as String,
      updatedAtIso: (json['updatedAtIso'] ?? '') as String,
      values: rawValues.map(
        (key, value) => MapEntry(key, (value ?? '').toString()),
      ),
      fieldLabels: rawLabels.map(
        (key, value) => MapEntry(key, (value ?? '').toString()),
      ),
      fieldSources: rawSources.map(
        (key, value) => MapEntry(key, (value ?? '').toString()),
      ),
      registryIds: registries,
      fieldDefinitions: rawDefinitions.map(
        (key, value) => MapEntry(
          key,
          RecordFieldDef.fromJson((value as Map).cast<String, dynamic>()),
        ),
      ),
    );
  }

  String encode() => jsonEncode(toJson());
  static RecordEntry decode(String raw) =>
      RecordEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class RecordSummary {
  final String recordEntryId;
  final String linkedReportId;
  final String procedure;
  final String diagnosis;
  final String reportDate;
  final String patientReference;
  final DateTime updatedAt;
  final Map<String, String> values;
  final Map<String, String> fieldLabels;
  final Map<String, String> fieldSources;
  final List<String> registryIds;

  const RecordSummary({
    required this.recordEntryId,
    required this.linkedReportId,
    required this.procedure,
    required this.diagnosis,
    required this.reportDate,
    required this.patientReference,
    required this.updatedAt,
    required this.values,
    this.fieldLabels = const <String, String>{},
    this.fieldSources = const <String, String>{},
    this.registryIds = const <String>[],
  });
}

class RecordFieldCatalog {
  static const reportId = RecordFieldDef(
    key: 'reportId',
    label: 'Report ID',
    hint: 'Unique report reference',
  );
  static const reportDate = RecordFieldDef(
    key: 'reportDate',
    label: 'Report Date',
    hint: 'Date the report was finalized',
  );
  static const subjectName = RecordFieldDef(
    key: 'subjectName',
    label: 'Subject Name',
    hint: 'Subject name or privacy-safe reference',
  );
  static const procedure = RecordFieldDef(
    key: 'procedure',
    label: 'Procedure / Report Type',
    hint: 'Select or type the procedure or report type',
    builtInSuggestions: [
      'Upper GI Endoscopy',
      'Colonoscopy',
      'Flexible Sigmoidoscopy',
      'ERCP',
      'Echocardiography',
      'Bronchoscopy',
      'Cystoscopy',
      'Ultrasound Scan',
    ],
  );
  static const indication = RecordFieldDef(
    key: 'indication',
    label: 'Indication',
    hint: 'Reason for the procedure',
    builtInSuggestions: [
      'Abdominal pain',
      'Upper GI bleeding',
      'Dysphagia',
      'Anemia',
      'Vomiting',
      'Surveillance',
      'Screening',
    ],
  );
  static const diagnosis = RecordFieldDef(
    key: 'diagnosis',
    label: 'Impression',
    hint: 'Main endoscopic impression or report conclusion',
    builtInSuggestions: [
      'Normal study',
      'Gastritis',
      'Esophagitis',
      'Duodenitis',
      'Gastric ulcer',
      'Colitis',
      'Hemorrhoids',
      'Polyp',
    ],
  );
  static const biopsyTaken = RecordFieldDef(
    key: 'biopsyTaken',
    label: 'Biopsy Taken',
    hint: 'Whether biopsy was taken',
    builtInSuggestions: ['Yes', 'No'],
  );
  static const histologyResult = RecordFieldDef(
    key: 'histologyResult',
    label: 'Histology Result',
    hint: 'Histology or pathology result, if available',
  );
  static const intervention = RecordFieldDef(
    key: 'intervention',
    label: 'Intervention / Therapy',
    hint: 'Therapeutic intervention performed, if any',
  );
  static const complications = RecordFieldDef(
    key: 'complications',
    label: 'Complications',
    hint: 'Complications, if any',
    builtInSuggestions: ['None'],
  );
  static const recommendations = RecordFieldDef(
    key: 'recommendations',
    label: 'Recommendations',
    hint: 'Follow-up or management recommendation',
  );
  static const gender = RecordFieldDef(
    key: 'gender',
    label: 'Gender',
    hint: 'Subject gender, if relevant',
    builtInSuggestions: ['Male', 'Female'],
  );
  static const age = RecordFieldDef(
    key: 'age',
    label: 'Age',
    hint: 'Subject age, if relevant',
  );
  static const patientReference = RecordFieldDef(
    key: 'patientReference',
    label: 'Subject ID',
    hint: 'Subject identifier, initials, or other local reference',
  );
  static const doctor = RecordFieldDef(
    key: 'doctor',
    label: 'Doctor',
    hint: 'Consultant / operator / endoscopist',
  );
  static const facility = RecordFieldDef(
    key: 'facility',
    label: 'Facility',
    hint: 'Hospital, clinic, centre, or practice location',
  );

  static const coreFields = <RecordFieldDef>[
    reportId,
    reportDate,
    subjectName,
    procedure,
    indication,
    diagnosis,
    biopsyTaken,
    histologyResult,
    intervention,
    complications,
    recommendations,
    gender,
    age,
    patientReference,
    doctor,
    facility,
  ];

  // Default export/table keys are limited to stable system/identity fields.
  // Other fields (including Impression/Intervention/Recommendation) are exported
  // when they are actually present in records or explicitly created by the user,
  // template, procedure, or registry. This avoids blank "ghost fields".
  static const exportDefaultKeys = <String>[
    'reportId',
    'reportDate',
    'subjectName',
    'patientReference',
    'procedure',
    'doctor',
    'facility',
  ];

  static RecordFieldDef? byKey(String key) {
    for (final field in coreFields) {
      if (field.key == key) return field;
    }
    return null;
  }
}
