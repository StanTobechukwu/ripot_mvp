import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/core/services/engagement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReviewHarness {
  DateTime now = DateTime(2026, 11, 1);
  bool available = true;
  int availabilityChecks = 0;
  int requests = 0;
  int storeVisits = 0;
  Future<bool> Function()? availability;
  Future<void> Function()? request;
  Future<void> Function()? openStore;

  ReviewPromptController controller({
    bool enabled = true,
    Future<SharedPreferences> Function()? preferences,
  }) => ReviewPromptController(
    enabled: enabled,
    preferences: preferences,
    now: () => now,
    isAvailable: () async {
      availabilityChecks++;
      return availability == null ? available : await availability!();
    },
    requestReview: () async {
      requests++;
      await request?.call();
    },
    openStoreListing: () async {
      storeVisits++;
      await openStore?.call();
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  ReviewPromptController controller,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ReviewPromptHost(controller: controller, child: const SizedBox.shrink()),
  );
  addTearDown(controller.stop);
}

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<void> _returnToApp(WidgetTester tester) async {
  _background(tester);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'review.completedShares': 9});
  });

  test('review needs ten new shares and a ninety day cooldown', () {
    final now = DateTime(2026, 10, 31);
    expect(
      shouldRequestReview(shares: 9, lastRequestShares: 0, now: now),
      false,
    );
    expect(
      shouldRequestReview(shares: 10, lastRequestShares: 0, now: now),
      true,
    );
    expect(
      shouldRequestReview(
        shares: 20,
        lastRequestShares: 10,
        now: now,
        lastRequest: now.subtract(const Duration(days: 89)),
      ),
      false,
    );
    expect(
      shouldRequestReview(
        shares: 19,
        lastRequestShares: 10,
        now: now,
        lastRequest: now.subtract(const Duration(days: 91)),
      ),
      false,
    );
    expect(
      shouldRequestReview(
        shares: 20,
        lastRequestShares: 10,
        now: now,
        lastRequest: now.subtract(const Duration(days: 90)),
      ),
      true,
    );
  });

  testWidgets('Printing callback waits for return and completed request', (tester) async {
    final h = _ReviewHarness();
    final completion = Completer<void>();
    h.request = () => completion.future;
    final c = h.controller();
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, c);

    await c.reportShared();
    expect(prefs.getInt('review.completedShares'), 10);
    await tester.pump(const Duration(seconds: 2));
    expect(h.requests, 0);
    _background(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(h.requests, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 999));
    expect(h.requests, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(h.requests, 1);
    expect(prefs.getInt('review.lastRequestMs'), isNull);

    // Returning from Google's own surface cannot launch a second request.
    await _returnToApp(tester);
    expect(h.requests, 1);
    completion.complete();
    await tester.pump();
    expect(prefs.getInt('review.lastRequestShares'), 10);
    expect(prefs.getInt('review.lastRequestMs'), h.now.millisecondsSinceEpoch);
    await _returnToApp(tester);
    expect(h.requests, 1);
  });

  testWidgets('Share Plus callback after resume still schedules the request', (tester) async {
    final h = _ReviewHarness();
    final c = h.controller();
    await _mount(tester, c);
    await _returnToApp(tester);
    expect(h.requests, 0);
    await c.reportShared(waitForReturn: false);
    expect(h.requests, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(h.requests, 1);
  });

  testWidgets('return waits for queued share counts and does not lose increments', (tester) async {
    SharedPreferences.setMockInitialValues({'review.completedShares': 0});
    final prefs = await SharedPreferences.getInstance();
    final pendingRead = Completer<SharedPreferences>();
    final h = _ReviewHarness();
    final c = h.controller(preferences: () => pendingRead.future);
    await _mount(tester, c);
    final shares = List.generate(10, (_) => c.reportShared());
    await _returnToApp(tester);
    expect(h.requests, 0);
    pendingRead.complete(prefs);
    await Future.wait(shares);
    await tester.pump();
    expect(prefs.getInt('review.completedShares'), 10);
    expect(h.requests, 1);
  });

  testWidgets('leaving during availability check cannot launch in background', (tester) async {
    final pendingAvailability = Completer<bool>();
    final h = _ReviewHarness()..availability = () => pendingAvailability.future;
    final c = h.controller();
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, c);
    await c.reportShared();
    await _returnToApp(tester);
    expect(h.availabilityChecks, 1);
    _background(tester);
    pendingAvailability.complete(true);
    await tester.pump();
    expect(h.requests, 0);
    expect(prefs.getInt('review.lastRequestMs'), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(h.requests, 1);
  });

  testWidgets('quick return during availability check schedules a fresh foreground check', (tester) async {
    final pendingAvailability = Completer<bool>();
    final h = _ReviewHarness()..availability = () => pendingAvailability.future;
    final c = h.controller();
    await _mount(tester, c);
    await c.reportShared();
    await _returnToApp(tester);
    expect(h.availabilityChecks, 1);
    await _returnToApp(tester);
    pendingAvailability.complete(true);
    await tester.pump();
    expect(h.requests, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(h.requests, 1);
  });

  testWidgets('failed API request backs off without spending the 90-day cooldown', (tester) async {
    final h = _ReviewHarness()
      ..request = () async => throw StateError('Play unavailable');
    final c = h.controller();
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, c);
    await c.reportShared();
    await _returnToApp(tester);
    expect(h.requests, 1);
    expect(prefs.getInt('review.lastRequestShares'), isNull);
    expect(prefs.getInt('review.lastRequestMs'), isNull);
    expect(prefs.getInt('review.lastFailedAttemptMs'), h.now.millisecondsSinceEpoch);
    await _returnToApp(tester);
    expect(h.requests, 1);

    h.now = h.now.add(const Duration(days: 1));
    h.request = null;
    await _returnToApp(tester);
    expect(h.requests, 2);
    expect(prefs.getInt('review.lastRequestShares'), 10);
    expect(prefs.getInt('review.lastFailedAttemptMs'), isNull);
  });

  testWidgets('unavailable API can retry later without ten more shares', (tester) async {
    final h = _ReviewHarness()..available = false;
    final c = h.controller();
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, c);
    await c.reportShared();
    await _returnToApp(tester);
    expect(h.requests, 0);
    expect(h.availabilityChecks, 1);
    expect(prefs.getInt('review.lastRequestMs'), isNull);
    await _returnToApp(tester);
    expect(h.availabilityChecks, 1);
    h.available = true;
    h.now = h.now.add(const Duration(days: 1));
    await _returnToApp(tester);
    expect(h.requests, 1);
  });

  testWidgets('updates preserve old counters and successful request cooldown', (tester) async {
    final h = _ReviewHarness();
    SharedPreferences.setMockInitialValues({
      'review.completedShares': 20,
      'review.lastRequestShares': 10,
      'review.lastRequestMs': h.now.subtract(const Duration(days: 89)).millisecondsSinceEpoch,
    });
    final c = h.controller();
    await _mount(tester, c);
    await _returnToApp(tester);
    expect(h.requests, 0);
    h.now = h.now.add(const Duration(days: 1));
    await _returnToApp(tester);
    expect(h.requests, 1);
    // API success with no visible Google dialog still counts as a request.
    await _returnToApp(tester);
    expect(h.requests, 1);
    final replacement = h.controller();
    await tester.pumpWidget(
      ReviewPromptHost(controller: replacement, child: const SizedBox.shrink()),
    );
    addTearDown(replacement.stop);
    await _returnToApp(tester);
    expect(h.requests, 1);
  });

  testWidgets('manual rating bypasses availability and cooldown without claiming a review', (tester) async {
    final h = _ReviewHarness()..available = false;
    SharedPreferences.setMockInitialValues({
      'review.completedShares': 20,
      'review.lastRequestShares': 10,
      'review.lastRequestMs': h.now.millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final c = h.controller();
    await _mount(tester, c);
    await c.openStoreListing();
    expect(h.storeVisits, 1);
    expect(h.requests, 0);
    expect(h.availabilityChecks, 0);
    expect(prefs.getInt('review.completedShares'), 20);
    expect(prefs.getInt('review.lastRequestShares'), 10);
    expect(prefs.getInt('review.lastRequestMs'), h.now.millisecondsSinceEpoch);
  });

  testWidgets('returning from manual store visit does not prompt again', (tester) async {
    SharedPreferences.setMockInitialValues({'review.completedShares': 10});
    final h = _ReviewHarness();
    final c = h.controller();
    await _mount(tester, c);
    await c.openStoreListing();
    await _returnToApp(tester);
    expect(h.storeVisits, 1);
    expect(h.requests, 0);
  });

  testWidgets('disposal cancels a pending foreground request', (tester) async {
    final h = _ReviewHarness();
    final c = h.controller();
    await _mount(tester, c);
    await c.reportShared();
    _background(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(h.requests, 0);
  });

  testWidgets('other platforms do not record shares or request reviews', (tester) async {
    final h = _ReviewHarness();
    final c = h.controller(enabled: false);
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, c);
    await c.reportShared();
    await _returnToApp(tester);
    expect(prefs.getInt('review.completedShares'), 9);
    expect(h.requests, 0);
    expect(h.availabilityChecks, 0);
  });

  testWidgets('preference failures never fail the share action', (tester) async {
    final h = _ReviewHarness();
    final c = h.controller(preferences: () async => throw StateError('Storage unavailable'));
    await _mount(tester, c);
    await expectLater(c.reportShared(), completes);
    await _returnToApp(tester);
    expect(h.requests, 0);
    expect(tester.takeException(), isNull);
  });
}
