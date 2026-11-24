// ignore_for_file: depend_on_referenced_packages
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/onboarding_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/apps/paw_app_page.dart';
import 'package:dsh_app/ui/onboarding/connect_page.dart';
import 'package:dsh_app/ui/onboarding/welcome_page.dart';
import 'package:dsh_app/ui/shell/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../onboarding/local_optional_support.dart';
import '../../shell/golden_harness.dart';
import '../../web/support/fake_webview.dart';

void main() {
  const cases = [
    ('first run', missingStatus, OnboardingPrefs(loaded: true)),
    ('setup without a key', stoppedStatus, OnboardingPrefs(loaded: true, welcomeSeen: true)),
    ('disconnected home', missingStatus, OnboardingPrefs(loaded: true, welcomeSeen: true, localDeclined: true)),
  ];
  for (final (screen, status, prefs) in cases) {
    testWidgets('PAW opens from $screen and returns to it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final web = FakeWebViewPlatform();
      WebViewPlatform.instance = web;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      final runtime = RecordingLocalRuntime(LocalRuntimeState(loaded: true, status: status));
      await tester.pumpWidget(
        goldenApp(
          home: const RootGate(home: Scaffold(body: Text('DSH home'))),
          brightness: Brightness.light,
          prefs: prefs,
          overrides: [
            localRuntimeProvider.overrideWith(() => runtime),
            settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true, autoStartLocal: false))),
            footprint(roomyPhone),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final original = switch (screen) {
        'first run' => find.byType(WelcomePage),
        'setup without a key' => find.byType(ConnectPage),
        _ => find.text('DSH home'),
      };
      expect(original, findsOneWidget);
      // ConnectPage already starts the installed local engine to support its own sign-in.
      final callsBeforePaw = List<String>.of(runtime.calls);
      if (status == missingStatus) expect(callsBeforePaw, isEmpty);
      final container = ProviderScope.containerOf(tester.element(find.byType(RootGate)));
      final entry = find.text('进入 PAW');
      expect(entry.hitTestable(), findsOneWidget);
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PawAppPage), findsOneWidget);
      expect(web.controller.loads, [PawAppPage.entry]);
      expect(original, findsNothing);
      web.controller.finish();
      await tester.pump();
      // Exit the pushed route. Web history and system back are tested on PawAppPage.
      Navigator.of(tester.element(find.byType(PawAppPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(original, findsOneWidget);
      expect(entry.hitTestable(), findsOneWidget);
      expect(container.read(onboardingPrefsProvider), same(prefs));
      expect(runtime.calls, callsBeforePaw);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
