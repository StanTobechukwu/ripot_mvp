import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts PDF share actions, never report contents or recipients.
bool shouldRequestReview({
  required int shares,
  required int lastRequestShares,
  required DateTime now,
  DateTime? lastRequest,
}) =>
    shares - lastRequestShares >= 10 &&
    (lastRequest == null || now.difference(lastRequest).inDays >= 90);

/// Waits for Android's share surface to close before requesting a review.
/// Google may complete a request without showing its dialog or receiving a rating.
class ReviewPromptController with WidgetsBindingObserver {
  ReviewPromptController({
    bool? enabled,
    Future<SharedPreferences> Function()? preferences,
    Future<bool> Function()? isAvailable,
    Future<void> Function()? requestReview,
    Future<void> Function()? openStoreListing,
    DateTime Function()? now,
    this.resumeDelay = const Duration(seconds: 1),
  }) : enabled = enabled ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _isAvailable = isAvailable ?? InAppReview.instance.isAvailable,
       _requestReview = requestReview ?? InAppReview.instance.requestReview,
       _openStoreListing = openStoreListing ??
           (() => InAppReview.instance.openStoreListing()),
       _now = now ?? DateTime.now;

  final bool enabled;
  final Duration resumeDelay;
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function() _isAvailable;
  final Future<void> Function() _requestReview;
  final Future<void> Function() _openStoreListing;
  final DateTime Function() _now;
  Future<void> _pendingShares = Future<void>.value();
  Timer? _resumeTimer;
  bool _started = false;
  bool _waitingForReturn = false;
  bool _requestInFlight = false;
  bool _skipNextResume = false;
  int _epoch = 0;

  void start() {
    if (!enabled || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _cancelScheduledRequest();
  }

  void _cancelScheduledRequest() {
    _epoch++;
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  bool get _canRequest =>
      _started &&
      !_waitingForReturn &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _cancelScheduledRequest();
    if (state != AppLifecycleState.resumed) return;
    _waitingForReturn = false;
    if (_skipNextResume) {
      _skipNextResume = false;
      return;
    }
    _scheduleRequest();
  }

  /// Printing reports success when it OPENS the Android chooser. Its callers
  /// must wait for a later resume. Share Plus reports after the chooser returns,
  /// so it can use waitForReturn: false and still observes the foreground delay.
  Future<void> reportShared({bool waitForReturn = true}) {
    if (!enabled) return Future<void>.value();
    _cancelScheduledRequest();
    _waitingForReturn = waitForReturn;
    _pendingShares = _pendingShares.then((_) async {
      final prefs = await _preferences();
      final count = (prefs.getInt('review.completedShares') ?? 0) + 1;
      await prefs.setInt('review.completedShares', count);
    }).catchError((Object _) {
      // An optional review request must never break PDF sharing.
    });
    return _pendingShares.then((_) {
      if (!waitForReturn) _scheduleRequest();
    });
  }

  void _scheduleRequest() {
    if (!_canRequest || _requestInFlight) return;
    _resumeTimer?.cancel();
    final epoch = _epoch;
    _resumeTimer = Timer(resumeDelay, () {
      _resumeTimer = null;
      unawaited(_tryRequest(epoch));
    });
  }

  Future<void> _tryRequest(int epoch) async {
    bool stillReady() => _canRequest && epoch == _epoch;
    if (!stillReady() || _requestInFlight) return;
    _requestInFlight = true;
    SharedPreferences? prefs;
    try {
      await _pendingShares;
      prefs = await _preferences();
      if (!stillReady()) return;
      final count = prefs.getInt('review.completedShares') ?? 0;
      final lastTime = prefs.getInt('review.lastRequestMs');
      final now = _now();
      if (!shouldRequestReview(
        shares: count,
        lastRequestShares: prefs.getInt('review.lastRequestShares') ?? 0,
        now: now,
        lastRequest: lastTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastTime),
      )) return;
      final lastFailure = prefs.getInt('review.lastFailedAttemptMs');
      if (lastFailure != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastFailure)) <
              const Duration(days: 1)) return;
      if (!await _isAvailable()) {
        await prefs.setInt('review.lastFailedAttemptMs', now.millisecondsSinceEpoch);
        return;
      }
      if (!stillReady()) return;
      await _requestReview();
      // Successful API completion does NOT prove the dialog appeared. Retain
      // the cooldown even when Google silently suppresses its review surface.
      await prefs.setInt('review.lastRequestMs', _now().millisecondsSinceEpoch);
      await prefs.setInt('review.lastRequestShares', count);
      await prefs.remove('review.lastFailedAttemptMs');
    } catch (_) {
      // A failed API call does not consume ten shares or the 90-day cooldown.
      // Back off for a day rather than retrying on every foreground transition.
      try {
        await prefs?.setInt('review.lastFailedAttemptMs', _now().millisecondsSinceEpoch);
      } catch (_) {
        // Local preference errors must not interrupt the report workflow.
      }
    } finally {
      _requestInFlight = false;
    }
  }

  /// Explicit user action: opens the listing, independently of Google's quota.
  Future<void> openStoreListing() async {
    _cancelScheduledRequest();
    _skipNextResume = true;
    try {
      await _openStoreListing();
    } catch (_) {
      _skipNextResume = false;
      rethrow;
    }
  }
}

class EngagementService {
  static final controller = ReviewPromptController();

  static Future<void> reportShared({bool waitForReturn = true}) =>
      controller.reportShared(waitForReturn: waitForReturn);

  static Future<void> openStoreListing() => controller.openStoreListing();
}

/// Keeps the review observer alive across report previews and navigation.
class ReviewPromptHost extends StatefulWidget {
  const ReviewPromptHost({super.key, required this.child, this.controller});

  final Widget child;
  final ReviewPromptController? controller;

  @override
  State<ReviewPromptHost> createState() => _ReviewPromptHostState();
}

class _ReviewPromptHostState extends State<ReviewPromptHost> {
  late ReviewPromptController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? EngagementService.controller;
    _controller.start();
  }

  @override
  void didUpdateWidget(ReviewPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller ?? EngagementService.controller;
    if (identical(next, _controller)) return;
    _controller.stop();
    _controller = next;
    _controller.start();
  }

  @override
  void dispose() {
    _controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
