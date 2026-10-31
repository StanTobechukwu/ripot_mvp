import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts completed PDF share actions, never report contents or recipients.
bool shouldRequestReview({
  required int shares,
  required int lastRequestShares,
  required DateTime now,
  DateTime? lastRequest,
}) =>
    shares - lastRequestShares >= 10 &&
    (lastRequest == null || now.difference(lastRequest).inDays >= 90);

class EngagementService {
  static Future<void> _pending = Future<void>.value();
  static Future<void> reportShared() {
    _pending = _pending.then((_) => _record()).catchError((Object _) {});
    return _pending;
  }

  static Future<void> _record() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt('review.completedShares') ?? 0) + 1;
    await prefs.setInt('review.completedShares', count);
    final lastCount = prefs.getInt('review.lastRequestShares') ?? 0;
    final lastTime = prefs.getInt('review.lastRequestMs');
    final now = DateTime.now();
    if (!shouldRequestReview(
      shares: count,
      lastRequestShares: lastCount,
      now: now,
      lastRequest: lastTime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastTime),
    ))
      return;
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return;
    // Google decides whether to show a dialog. Never assume a rating was made.
    await prefs.setInt('review.lastRequestShares', count);
    await prefs.setInt('review.lastRequestMs', now.millisecondsSinceEpoch);
    await review.requestReview();
  }
}
