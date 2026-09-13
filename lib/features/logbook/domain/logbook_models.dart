import 'dart:convert';
import 'dart:typed_data';

// Backup and local storage use the same strictly versioned, JSON-only schema.
Map<String, dynamic> object(Object? value) {
  if (value is! Map) throw const FormatException('Expected an object');
  return Map<String, dynamic>.from(value);
}

String textValue(
  Map<String, dynamic> j,
  String key, {
  bool required = false,
  int max = 20000,
}) {
  final v = j[key];
  if (v is! String || v.length > max || (required && v.trim().isEmpty)) {
    throw FormatException('Invalid $key');
  }
  return v;
}

DateTime dateValue(Map<String, dynamic> j, String key) =>
    DateTime.parse(textValue(j, key, required: true, max: 40));
int intValue(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! int || v < 0 || v > 9007199254740991) {
    throw FormatException('Invalid $key');
  }
  return v;
}

List<T> items<T>(
  Map<String, dynamic> j,
  String key,
  T Function(Map<String, dynamic>) read, {
  int max = 100000,
}) {
  final v = j[key];
  if (v is! List || v.length > max) throw FormatException('Invalid $key');
  return List.unmodifiable(v.map((e) => read(object(e))));
}

enum ProcedureRole { performer, assistant, observer }

extension RoleLabel on ProcedureRole {
  String get label => switch (this) {
    ProcedureRole.performer => 'Performer',
    ProcedureRole.assistant => 'Assistant',
    ProcedureRole.observer => 'Observer',
  };
}

class LogDoctor {
  final String id, name, detail;
  const LogDoctor({required this.id, required this.name, this.detail = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'detail': detail};
  factory LogDoctor.fromJson(Map<String, dynamic> j) => LogDoctor(
    id: textValue(j, 'id', required: true, max: 160),
    name: textValue(j, 'name', required: true, max: 200),
    detail: textValue(j, 'detail', max: 200),
  );
}

class LogParticipant {
  final String doctorId;
  final ProcedureRole role;
  final bool supervised;
  const LogParticipant(this.doctorId, this.role, {this.supervised = false});
  Map<String, dynamic> toJson() => {
    'doctorId': doctorId,
    'role': role.name,
    'supervised': supervised,
  };
  factory LogParticipant.fromJson(Map<String, dynamic> j) {
    if (j['supervised'] is! bool) {
      throw const FormatException('Invalid supervision');
    }
    return LogParticipant(
      textValue(j, 'doctorId', required: true, max: 160),
      ProcedureRole.values.byName(textValue(j, 'role')),
      supervised: j['supervised'] as bool,
    );
  }
}

class LogField {
  final String id, label, value;
  const LogField(this.id, this.label, this.value);
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'value': value};
  factory LogField.fromJson(Map<String, dynamic> j) => LogField(
    textValue(j, 'id', required: true, max: 200),
    textValue(j, 'label', required: true, max: 500),
    textValue(j, 'value'),
  );
}

class LogData {
  final String procedure,
      facility,
      reference,
      notes,
      supervisorId,
      reportAuthor;
  final DateTime procedureDate;
  final List<LogParticipant> participants;
  final List<LogField> fields;
  LogData({
    required this.procedure,
    required this.procedureDate,
    this.facility = '',
    this.reference = '',
    this.notes = '',
    this.supervisorId = '',
    this.reportAuthor = '',
    List<LogParticipant> participants = const [],
    List<LogField> fields = const [],
  }) : participants = List.unmodifiable(participants),
       fields = List.unmodifiable(fields);
  Map<String, dynamic> toJson() => {
    'procedure': procedure,
    'procedureDate': procedureDate.toIso8601String(),
    'facility': facility,
    'reference': reference,
    'notes': notes,
    'supervisorId': supervisorId,
    'reportAuthor': reportAuthor,
    'participants': participants.map((p) => p.toJson()).toList(),
    'fields': fields.map((f) => f.toJson()).toList(),
  };
  factory LogData.fromJson(Map<String, dynamic> j) {
    final participants = items(
      j,
      'participants',
      LogParticipant.fromJson,
      max: 50,
    );
    if (participants.isEmpty ||
        participants.map((p) => p.doctorId).toSet().length !=
            participants.length) {
      throw const FormatException('Choose each participating doctor once');
    }
    final fields = items(j, 'fields', LogField.fromJson, max: 500);
    if (fields.map((f) => f.id).toSet().length != fields.length) {
      throw const FormatException('Duplicate log field');
    }
    return LogData(
      procedure: textValue(j, 'procedure', required: true, max: 200),
      procedureDate: dateValue(j, 'procedureDate'),
      facility: textValue(j, 'facility', max: 300),
      reference: textValue(j, 'reference', max: 300),
      notes: textValue(j, 'notes'),
      supervisorId: textValue(j, 'supervisorId', max: 160),
      reportAuthor: textValue(j, 'reportAuthor', max: 300),
      participants: participants,
      fields: fields,
    );
  }
}

class LogSignature {
  final int revision;
  final LogData snapshot;
  final String doctorId, signerName, pngBase64;
  final DateTime recordedAt;
  final Map<String, String> doctorNames;
  LogSignature({
    required this.revision,
    required this.snapshot,
    required this.doctorId,
    required this.signerName,
    required this.pngBase64,
    required this.recordedAt,
    required Map<String, String> doctorNames,
  }) : doctorNames = Map.unmodifiable(doctorNames);
  Map<String, dynamic> toJson() => {
    'revision': revision,
    'snapshot': snapshot.toJson(),
    'doctorId': doctorId,
    'signerName': signerName,
    'pngBase64': pngBase64,
    'recordedAt': recordedAt.toIso8601String(),
    'doctorNames': doctorNames,
  };
  factory LogSignature.fromJson(Map<String, dynamic> j) {
    final png = textValue(j, 'pngBase64', required: true, max: 2000000);
    final bytes = base64Decode(png);
    if (bytes.length < 24 ||
        bytes[0] != 137 ||
        ascii.decode(bytes.sublist(1, 4), allowInvalid: true) != 'PNG') {
      throw const FormatException('Invalid signature image');
    }
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16), height = header.getUint32(20);
    if (width == 0 || height == 0 || width > 4096 || height > 2048 || width * height > 4000000) {
      throw const FormatException('Signature dimensions are invalid');
    }
    final names = object(j['doctorNames']).map((k, v) {
      if (v is! String || v.length > 300) {
        throw const FormatException('Invalid doctor name');
      }
      return MapEntry(k, v);
    });
    final signature = LogSignature(
      revision: intValue(j, 'revision'),
      snapshot: LogData.fromJson(object(j['snapshot'])),
      doctorId: textValue(j, 'doctorId', required: true, max: 160),
      signerName: textValue(j, 'signerName', required: true, max: 200),
      pngBase64: png,
      recordedAt: dateValue(j, 'recordedAt'),
      doctorNames: names,
    );
    if (signature.revision < 1 ||
        names[signature.doctorId] != signature.signerName ||
        !names.containsKey(signature.doctorId) ||
        signature.snapshot.participants.any(
          (p) => !names.containsKey(p.doctorId),
        ) ||
        (signature.snapshot.supervisorId.isNotEmpty &&
            !names.containsKey(signature.snapshot.supervisorId))) {
      throw const FormatException('Incomplete signed snapshot');
    }
    return signature;
  }
}

class LogEntry {
  final String id, linkedReportId;
  final DateTime createdAt, updatedAt;
  final int revision;
  final LogData data;
  final List<LogSignature> signatures;
  LogEntry({
    required this.id,
    this.linkedReportId = '',
    required this.createdAt,
    required this.updatedAt,
    required this.data,
    this.revision = 1,
    List<LogSignature> signatures = const [],
  }) : signatures = List.unmodifiable(signatures);
  LogSignature? get currentSignature {
    for (final s in signatures.reversed) {
      if (s.revision == revision) return s;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'linkedReportId': linkedReportId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
    'data': data.toJson(),
    'signatures': signatures.map((s) => s.toJson()).toList(),
  };
  factory LogEntry.fromJson(Map<String, dynamic> j) {
    final entry = LogEntry(
      id: textValue(j, 'id', required: true, max: 160),
      linkedReportId: textValue(j, 'linkedReportId', max: 160),
      createdAt: dateValue(j, 'createdAt'),
      updatedAt: dateValue(j, 'updatedAt'),
      revision: intValue(j, 'revision'),
      data: LogData.fromJson(object(j['data'])),
      signatures: items(j, 'signatures', LogSignature.fromJson, max: 1000),
    );
    if (entry.revision < 1 ||
        entry.signatures.any((s) => s.revision > entry.revision) ||
        entry.signatures.map((s) => s.revision).toSet().length !=
            entry.signatures.length) {
      throw const FormatException('Invalid signed revisions');
    }
    final signed = entry.currentSignature;
    if (signed != null &&
        jsonEncode(signed.snapshot.toJson()) != jsonEncode(entry.data.toJson())) {
      throw const FormatException('Signed entry has changed');
    }
    return entry;
  }
}

class LogbookData {
  final List<LogDoctor> doctors;
  final List<LogEntry> entries;
  final String meId;
  final int sequence, createdCount, backedSequence, backedCreatedCount;
  final DateTime? backedAt, snoozedUntil, dirtySince;
  LogbookData({
    List<LogDoctor> doctors = const [],
    List<LogEntry> entries = const [],
    this.meId = '',
    this.sequence = 0,
    this.createdCount = 0,
    this.backedSequence = 0,
    this.backedCreatedCount = 0,
    this.backedAt,
    this.snoozedUntil,
    this.dirtySince,
  }) : doctors = List.unmodifiable(doctors),
       entries = List.unmodifiable(entries);
  LogbookData copyWith({
    List<LogDoctor>? doctors,
    List<LogEntry>? entries,
    String? meId,
    int? sequence,
    int? createdCount,
    int? backedSequence,
    int? backedCreatedCount,
    DateTime? backedAt,
    DateTime? snoozedUntil,
    DateTime? dirtySince,
  }) => LogbookData(
    doctors: doctors ?? this.doctors,
    entries: entries ?? this.entries,
    meId: meId ?? this.meId,
    sequence: sequence ?? this.sequence,
    createdCount: createdCount ?? this.createdCount,
    backedSequence: backedSequence ?? this.backedSequence,
    backedCreatedCount: backedCreatedCount ?? this.backedCreatedCount,
    backedAt: backedAt ?? this.backedAt,
    snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    dirtySince: dirtySince ?? this.dirtySince,
  );
  bool get dirty => sequence > backedSequence;
  bool backupDue(DateTime now) =>
      dirty &&
      !(snoozedUntil?.isAfter(now) ?? false) &&
      (createdCount - backedCreatedCount >= 20 ||
          now.difference(dirtySince ?? now).inDays >= 7);
  LogDoctor? doctor(String id) {
    for (final d in doctors) {
      if (d.id == id) return d;
    }
    return null;
  }

  LogEntry? entry(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'format': 'ripot-logbook',
    'version': 1,
    'doctors': doctors.map((d) => d.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'meId': meId,
    'sequence': sequence,
    'createdCount': createdCount,
    'backedSequence': backedSequence,
    'backedCreatedCount': backedCreatedCount,
    'backedAt': backedAt?.toIso8601String(),
    'snoozedUntil': snoozedUntil?.toIso8601String(),
    'dirtySince': dirtySince?.toIso8601String(),
  };
  factory LogbookData.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 'ripot-logbook' || j['version'] != 1) {
      throw const FormatException('Unsupported Logbook version');
    }
    DateTime? optionalDate(String key) =>
        j[key] == null ? null : dateValue(j, key);
    final data = LogbookData(
      doctors: items(j, 'doctors', LogDoctor.fromJson, max: 10000),
      entries: items(j, 'entries', LogEntry.fromJson),
      meId: textValue(j, 'meId', max: 160),
      sequence: intValue(j, 'sequence'),
      createdCount: intValue(j, 'createdCount'),
      backedSequence: intValue(j, 'backedSequence'),
      backedCreatedCount: intValue(j, 'backedCreatedCount'),
      backedAt: optionalDate('backedAt'),
      snoozedUntil: optionalDate('snoozedUntil'),
      dirtySince: optionalDate('dirtySince'),
    );
    final ids = data.doctors.map((d) => d.id).toSet();
    if (ids.length != data.doctors.length ||
        data.entries.map((e) => e.id).toSet().length != data.entries.length ||
        (data.meId.isNotEmpty && !ids.contains(data.meId)) ||
        data.backedSequence > data.sequence ||
        data.backedCreatedCount > data.createdCount ||
        data.createdCount < data.entries.length) {
      throw const FormatException('Invalid Logbook identity or counters');
    }
    final linked = data.entries
        .where((e) => e.linkedReportId.isNotEmpty)
        .map((e) => e.linkedReportId)
        .toList();
    if (linked.toSet().length != linked.length) {
      throw const FormatException('Duplicate report log');
    }
    for (final e in data.entries) {
      if (e.data.participants.any((p) => !ids.contains(p.doctorId)) ||
          (e.data.supervisorId.isNotEmpty &&
              !ids.contains(e.data.supervisorId)) ||
          e.signatures.any(
            (s) =>
                !ids.contains(s.doctorId) ||
                s.snapshot.participants.any((p) => !ids.contains(p.doctorId)),
          )) {
        throw const FormatException('Missing doctor in Logbook');
      }
    }
    return data;
  }
}
