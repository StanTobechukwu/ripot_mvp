/// Firestore REST's typed JSON representation. App models continue to receive
/// ordinary Dart maps, lists, numbers and DateTimes.
class FirestoreValues {
  static Map<String, dynamic> encodeFields(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, encode(value)));

  static Map<String, dynamic> encode(Object? value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double && value.isFinite) return {'doubleValue': value};
    if (value is String) return {'stringValue': value};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {'fields': encodeFields(value)},
      };
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(encode).toList()},
      };
    }
    throw ArgumentError('Unsupported Firestore field value.');
  }

  static Map<String, dynamic> decodeFields(Object? fields) {
    if (fields == null) return {};
    if (fields is! Map<String, dynamic>) {
      throw const FormatException('Invalid Firestore document.');
    }
    return fields.map((key, value) => MapEntry(key, decode(value)));
  }

  static dynamic decode(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid Firestore field.');
    }
    if (raw.containsKey('nullValue')) return null;
    if (raw.containsKey('stringValue')) return raw['stringValue'] as String;
    if (raw.containsKey('booleanValue')) return raw['booleanValue'] as bool;
    if (raw.containsKey('integerValue')) {
      return int.parse(raw['integerValue'] as String);
    }
    if (raw.containsKey('doubleValue')) {
      return (raw['doubleValue'] as num).toDouble();
    }
    if (raw.containsKey('timestampValue')) {
      return DateTime.parse(raw['timestampValue'] as String);
    }
    if (raw.containsKey('mapValue')) {
      return decodeFields((raw['mapValue'] as Map)['fields']);
    }
    if (raw.containsKey('arrayValue')) {
      return ((raw['arrayValue'] as Map)['values'] as List? ?? [])
          .map(decode)
          .toList();
    }
    throw const FormatException('Unsupported Firestore field.');
  }

  /// Merge leaves, preserving unspecified siblings just as SetOptions(merge:
  /// true) does. Empty maps replace the map; arrays are an atomic field value.
  static List<String> mergeMask(
    Map<String, dynamic> data, [
    List<String> parent = const [],
  ]) {
    final result = <String>[];
    for (final entry in data.entries) {
      final path = [...parent, entry.key];
      if (entry.value is Map<String, dynamic> &&
          (entry.value as Map).isNotEmpty) {
        result.addAll(mergeMask(entry.value as Map<String, dynamic>, path));
      } else {
        result.add(path.map(_fieldPath).join('.'));
      }
    }
    return result;
  }

  static String _fieldPath(String value) {
    if (RegExp(r'^[a-zA-Z_][a-zA-Z_0-9]*$').hasMatch(value)) return value;
    return '`${value.replaceAll(r'\', r'\\').replaceAll('`', r'\`')}`';
  }
}
