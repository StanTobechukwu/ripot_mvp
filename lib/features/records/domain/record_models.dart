import 'dart:convert';

class RecordFieldDef {
  final String key;
  final String label;
  final String hint;
  final List<String> builtInSuggestions;
  final bool isSystem;

  const RecordFieldDef({
    required this.key,
    required this.label,
    required this.hint,
    this.builtInSuggestions = const [],
    this.isSystem = true,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'hint': hint,
        'builtInSuggestions': builtInSuggestions,
        'isSystem': isSystem,
      };

  factory RecordFieldDef.fromJson(Map<String, dynamic> json) {
    final suggestions = (json['builtInSuggestions'] as List?)?.map((e) => e.toString()).toList(growable: false) ?? const <String>[];
    return RecordFieldDef(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      hint: (json['hint'] ?? '').toString(),
      builtInSuggestions: suggestions,
      isSystem: (json['isSystem'] ?? false) == true,
    );
  }
}

class RecordEntry {
  final String recordEntryId;
  final String linkedReportId;
  final String createdAtIso;
  final String updatedAtIso;
  final Map<String, String> values;

  const RecordEntry({
    required this.recordEntryId,
    required this.linkedReportId,
    required this.createdAtIso,
    required this.updatedAtIso,
    required this.values,
  });

  String valueOf(String key) => values[key]?.trim() ?? '';

  RecordEntry copyWith({
    String? recordEntryId,
    String? linkedReportId,
    String? createdAtIso,
    String? updatedAtIso,
    Map<String, String>? values,
  }) {
    return RecordEntry(
      recordEntryId: recordEntryId ?? this.recordEntryId,
      linkedReportId: linkedReportId ?? this.linkedReportId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      values: values ?? this.values,
    );
  }

  Map<String, dynamic> toJson() => {
        'recordEntryId': recordEntryId,
        'linkedReportId': linkedReportId,
        'createdAtIso': createdAtIso,
        'updatedAtIso': updatedAtIso,
        'values': values,
      };

  factory RecordEntry.fromJson(Map<String, dynamic> json) {
    final rawValues = (json['values'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return RecordEntry(
      recordEntryId: (json['recordEntryId'] ?? '') as String,
      linkedReportId: (json['linkedReportId'] ?? '') as String,
      createdAtIso: (json['createdAtIso'] ?? '') as String,
      updatedAtIso: (json['updatedAtIso'] ?? '') as String,
      values: rawValues.map((key, value) => MapEntry(key, (value ?? '').toString())),
    );
  }

  String encode() => jsonEncode(toJson());
  static RecordEntry decode(String raw) => RecordEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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

  const RecordSummary({
    required this.recordEntryId,
    required this.linkedReportId,
    required this.procedure,
    required this.diagnosis,
    required this.reportDate,
    required this.patientReference,
    required this.updatedAt,
    required this.values,
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
  static const procedure = RecordFieldDef(
    key: 'procedure',
    label: 'Procedure',
    hint: 'Select or type the procedure',
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
    label: 'Diagnosis',
    hint: 'Main diagnosis or impression',
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
  static const gender = RecordFieldDef(
    key: 'gender',
    label: 'Gender',
    hint: 'Patient gender',
    builtInSuggestions: ['Male', 'Female'],
  );
  static const age = RecordFieldDef(
    key: 'age',
    label: 'Age',
    hint: 'Patient age',
  );
  static const patientReference = RecordFieldDef(
    key: 'patientReference',
    label: 'Patient Reference',
    hint: 'Hospital card number, initials, or other local reference',
  );
  static const doctor = RecordFieldDef(
    key: 'doctor',
    label: 'Doctor',
    hint: 'Consultant / operator / endoscopist',
  );

  static const coreFields = <RecordFieldDef>[
    reportId,
    reportDate,
    procedure,
    indication,
    diagnosis,
    gender,
    age,
    patientReference,
    doctor,
  ];

  static const exportDefaultKeys = <String>[
    'reportId',
    'reportDate',
    'procedure',
    'indication',
    'diagnosis',
    'gender',
    'age',
    'patientReference',
    'doctor',
  ];

  static RecordFieldDef? byKey(String key) {
    for (final field in coreFields) {
      if (field.key == key) return field;
    }
    return null;
  }
}
