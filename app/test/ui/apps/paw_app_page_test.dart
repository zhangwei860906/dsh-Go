import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../web/support/fake_webview.dart';

import 'package:dsh_app/ui/apps/paw_app_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_app/ui/apps/app_center_page.dart';
import 'package:dsh_app/links/page_links.dart';

void main() {
  testWidgets('app center entry fits a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: buildLightTheme(), home: const AppCenterPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paw-app-entry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('test app scheme and bundled guide links stay usable', () {
    expect(pageLinkId(Uri.parse('dshgopaw://open/engine')), 'engine');
    expect(pageLinkId(Uri.parse('dshgo://open/engine')), 'engine');
  });

  test('PAW app permits its authenticated routes and rejects foreign frames', () {
    NavigationDecision check(String url) => PawAppPage.navigationPolicy(NavigationRequest(url: url, isMainFrame: true));

    expect(check('https://paw-43-106-15-201.sslip.io/paw/mobile'), NavigationDecision.navigate);
    expect(
      check('https://paw-43-106-15-201.sslip.io/v2/agent-ui/login?next=%2Fpaw%2Fmobile'),
      NavigationDecision.navigate,
    );
    expect(check('http://paw-43-106-15-201.sslip.io/paw/mobile'), NavigationDecision.prevent);
    expect(check('https://other.example/paw/mobile'), NavigationDecision.prevent);
    expect(check('https://paw-43-106-15-201.sslip.io.evil.example/paw/mobile'), NavigationDecision.prevent);
    expect(
      PawAppPage.navigationPolicy(NavigationRequest(url: 'https://other.example/embed', isMainFrame: false)),
      NavigationDecision.navigate,
    );
  });

  group('PAW back navigation', () {
    late FakeWebViewPlatform platform;

    setUp(() => WebViewPlatform.instance = platform = FakeWebViewPlatform());

    Future<FakeWebViewController> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(theme: buildLightTheme(), home: const AppCenterPage()));
      await tester.tap(find.byKey(const ValueKey('paw-app-entry')));
      await tester.pump();
      final web = platform.controller;
      expect(web.loads, [PawAppPage.entry]);
      web.finish();
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      return web;
    }

    Future<void> edgeSwipeBack(WidgetTester tester) async {
      final gesture = await tester.startGesture(const Offset(2, 300));
      await gesture.moveBy(const Offset(100, 0));
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('edge swipe returns from the trading agent in the same WebView', (tester) async {
      final web = await open(tester);
      final agent = PawAppPage.entry.resolve('/v2/agent-ui/index.html?project=trading&mobile_handoff=1');
      web.loads.add(agent);
      web.history = 1;

      await edgeSwipeBack(tester);
      expect(web.goBacks, 1);
      expect(web.loads, [PawAppPage.entry, agent]);
      expect(find.byKey(fakeWebViewKey), findsOneWidget);
    });

    testWidgets('system back uses the PAW shell history, then exits before login', (tester) async {
      final web = await open(tester);
      var depth = 1;
      web.history = 2; // mobile route and the login that preceded the shell
      final reads = <String>[];
      web.results = (script) {
        reads.add(script);
        return depth;
      };
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(reads.last, contains('history.state?.pawMobileShell?.depth'));
      expect(web.scripts, ['history.back()']);
      expect(web.goBacks, 0);
      expect(find.byKey(fakeWebViewKey), findsOneWidget);

      // A second intentional back follows after the transition debounce.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      depth = 0;
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(reads.last, contains('history.state?.pawMobileShell?.depth'));
      expect(web.scripts, ['history.back()']);
      expect(web.goBacks, 0);
      expect(find.byKey(const ValueKey('paw-app-entry')), findsOneWidget);
    });

    testWidgets('back leaves Owner login even when a redirect created history', (tester) async {
      final web = await open(tester);
      web.loads.add(PawAppPage.entry.resolve('/v2/agent-ui/login?next=%2Fpaw%2Fmobile'));
      web.history = 1;
      await edgeSwipeBack(tester);

      expect(web.goBacks, 0);
      expect(find.byKey(const ValueKey('paw-app-entry')), findsOneWidget);
    });

    testWidgets('history failure keeps PAW open until the user chooses to close', (tester) async {
      final web = await open(tester);
      web.history = 1;
      web.results = (_) => throw StateError('renderer unavailable');
      await edgeSwipeBack(tester);
      expect(web.goBacks, 0);
      expect(find.byKey(fakeWebViewKey), findsOneWidget);
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paw-app-entry')), findsOneWidget);
    });

    testWidgets('overlapping back requests advance only one entry', (tester) async {
      final web = await open(tester);
      web.history = 3;
      web.results = (_) => 2;
      final first = await tester.startGesture(const Offset(2, 300));
      await first.moveBy(const Offset(100, 0));
      await first.up();
      final second = await tester.startGesture(const Offset(2, 300));
      await second.moveBy(const Offset(100, 0));
      await second.up();
      await tester.pumpAndSettle();
      expect(web.scripts, ['history.back()']);
      expect(web.goBacks, 0);
      expect(find.byKey(fakeWebViewKey), findsOneWidget);
    });
  });
}
