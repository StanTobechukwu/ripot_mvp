import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/ids.dart';
import '../domain/access_state.dart';

class AccessRepository {
  static const _installationIdKey = 'access.installationId';
  static const _stateKey = 'access.state';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String> getOrCreateInstallationId() async {
    final prefs = await _prefs;
    final existing = prefs.getString(_installationIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final id = newId('usr');
    await prefs.setString(_installationIdKey, id);
    return id;
  }

  Future<AccessState> load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_stateKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final state = AccessState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final normalized = _normalizeState(state);
        if (normalized != state) {
          await save(normalized);
        }
        return normalized;
      } catch (_) {}
    }

    final installationId = await getOrCreateInstallationId();
    final state = AccessState.initial(installationId: installationId, isEarlyUser: true);
    await save(state);
    return state;
  }

  Future<void> save(AccessState state) async {
    final prefs = await _prefs;
    final normalized = _normalizeState(state);
    await prefs.setString(_stateKey, jsonEncode(normalized.toJson()));
    await _syncToFirestore(normalized);
  }

  AccessState _normalizeState(AccessState state) {
    if (state.plan == RipotPlan.trial && !state.isTrialActive) {
      return state.copyWith(
        plan: RipotPlan.free,
        updatedAt: DateTime.now(),
      );
    }
    return state;
  }

  Future<void> _syncToFirestore(AccessState state) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('ripot_user_access').doc(state.installationId).set(
        state.toJson(),
        SetOptions(merge: true),
      );
    } catch (_) {
      // Stability first: never fail local save because cloud sync is unavailable.
    }
  }
}
