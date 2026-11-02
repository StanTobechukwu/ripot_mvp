import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/update/windows_update_prompt.dart';

void main() {
  const isStore = bool.fromEnvironment('RIPOT_MICROSOFT_STORE');

  testWidgets(
    'Store build does not start the standalone Windows installer update check',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var packageInfoCalls = 0;
      const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        packageInfoCalls++;
        return <String, String>{
          'appName': 'Ripot',
          'packageName': 'ripot',
          'version': '1.0.24',
          'buildNumber': '59',
        };
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: WindowsUpdatePrompt(child: Text('Report editor')),
        ),
      );
      await tester.pump();
      expect(find.text('Report editor'), findsOneWidget);
      expect(packageInfoCalls, 0);
      expect(find.text('Download update'), findsNothing);
    },
    skip: !isStore,
  );
}
