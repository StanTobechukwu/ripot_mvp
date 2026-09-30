import 'package:cloud_firestore/cloud_firestore.dart';

class CloudDocument {
  const CloudDocument(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

abstract interface class CloudDocuments {
  Future<Map<String, dynamic>?> get(
    String collection,
    String id, {
    bool serverOnly = false,
  });
  Future<List<CloudDocument>> query(
    String collection, {
    required Map<String, Object?> equals,
    int? limit,
  });
  Future<void> merge(String collection, String id, Map<String, dynamic> data);
  Future<void> delete(String collection, String id);
}

/// The existing FlutterFire implementation remains in use on Android and web.
class FirebaseCloudDocuments implements CloudDocuments {
  FirebaseCloudDocuments(this.db);
  final FirebaseFirestore db;
  @override
  Future<Map<String, dynamic>?> get(
    String collection,
    String id, {
    bool serverOnly = false,
  }) async =>
      (await db
              .collection(collection)
              .doc(id)
              .get(
                GetOptions(
                  source: serverOnly ? Source.server : Source.serverAndCache,
                ),
              ))
          .data();
  @override
  Future<List<CloudDocument>> query(
    String collection, {
    required Map<String, Object?> equals,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = db.collection(collection);
    for (final field in equals.entries) {
      query = query.where(field.key, isEqualTo: field.value);
    }
    if (limit != null) query = query.limit(limit);
    return (await query.get()).docs
        .map((doc) => CloudDocument(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<void> merge(String collection, String id, Map<String, dynamic> data) =>
      db.collection(collection).doc(id).set(data, SetOptions(merge: true));
  @override
  Future<void> delete(String collection, String id) =>
      db.collection(collection).doc(id).delete();
}
