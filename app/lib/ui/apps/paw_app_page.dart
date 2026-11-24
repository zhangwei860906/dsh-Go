import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/l10n.dart';
import '../web/web_file_chooser.dart';

/// An isolated app surface: no DSH Web layout CSS, toolbar overlay or timed
/// reload is injected into PAW's trading UI.
class PawAppPage extends StatefulWidget {
  const PawAppPage({super.key});

  static final Uri entry = Uri.parse('https://paw-43-106-15-201.sslip.io/paw/mobile');

  static bool _isPawUri(Uri? uri) => uri != null && uri.scheme == 'https' && uri.host == entry.host && uri.port == 443;

  static NavigationDecision navigationPolicy(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final uri = Uri.tryParse(request.url);
    return _isPawUri(uri) ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  @override
  State<PawAppPage> createState() => _PawAppPageState();
}

enum _BackTarget { shellHistory, documentHistory, host }

class _PawAppPageState extends State<PawAppPage> {
  final _chooser = WebFileChooser();
  late final WebViewController _web = WebViewController();
  bool _loading = true;
  bool _failed = false;
  int _progress = 0;
  bool _handlingBack = false;
  double _edgeDragDistance = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _chooser.attach(_web);
      await _web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final decision = PawAppPage.navigationPolicy(request);
            if (decision == NavigationDecision.prevent && request.isMainFrame) {
              _offerExternal(request.url);
            }
            return decision;
          },
          onPageStarted: (_) {
            if (!mounted) return;
            _chooser.invalidate();
            setState(() {
              _loading = true;
              _failed = false;
              _progress = 0;
            });
          },
          onProgress: (value) {
            if (mounted) {
              setState(() => _progress = value);
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
            }
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
        ),
      );
      await _web.loadRequest(PawAppPage.entry);
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<_BackTarget> _backTarget() async {
    final uri = Uri.tryParse(await _web.currentUrl() ?? '');
    if (uri == null || !PawAppPage._isPawUri(uri)) return _BackTarget.host;
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    if (path == '/v2/agent-ui/login') return _BackTarget.host;
    if (path == PawAppPage.entry.path || path == '/paw/mobile/index.html') {
      // The mobile shell pushes same-URL history for tabs, charts and dialogs.
      // Its depth zero is the boundary even when a login precedes it in WebKit.
      final depth = await _web.runJavaScriptReturningResult('Number(history.state?.pawMobileShell?.depth ?? -1)');
      if (depth is! num || depth < 0) throw StateError('PAW history is not ready');
      return depth > 0 ? _BackTarget.shellHistory : _BackTarget.host;
    }
    return await _web.canGoBack() ? _BackTarget.documentHistory : _BackTarget.host;
  }

  bool get _isCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _back() async {
    if (_handlingBack || !_isCurrent) return;
    _handlingBack = true;
    try {
      const timeout = Duration(seconds: 2);
      final target = await _backTarget().timeout(timeout);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      switch (target) {
        case _BackTarget.shellHistory:
          // Use the same History API as PAW's in-page back button: its
          // popstate listener restores the tab, chart and scroll position.
          await _web.runJavaScript('history.back()').timeout(timeout);
        case _BackTarget.documentHistory:
          await _web.goBack().timeout(timeout);
        case _BackTarget.host:
          Navigator.of(context).pop();
      }
    } on Object {
      // A busy WebView may still hold a trade draft. Closing the container
      // after a failed history query must be an explicit user choice.
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.pawBackUnavailable),
            persist: false,
            action: SnackBarAction(
              label: context.l10n.commonClose,
              onPressed: () {
                if (_isCurrent) Navigator.of(context).pop();
              },
            ),
          ),
        );
      }
    } finally {
      _handlingBack = false;
    }
  }

  void _offerExternal(String raw) {
    final uri = Uri.tryParse(raw);
    if (!mounted || uri == null || uri.scheme != 'https') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.pawExternalLink),
          persist: false,
          action: SnackBarAction(
            label: context.l10n.pawOpenBrowser,
            onPressed: () => unawaited(launchUrl(uri, mode: LaunchMode.externalApplication)),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _chooser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        // PAW owns the entire visible page. Do not add a DSH toolbar above
        // its trading UI; the iOS leading-edge gesture and system back route
        // through the same history-aware handler.
        body: SafeArea(
          child: Stack(
            children: [
              if (!_failed) WebViewWidget(controller: _web),
              if (_failed)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.pawLoadFailed),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => _web.loadRequest(PawAppPage.entry), child: Text(l10n.commonRetry)),
                    ],
                  ),
                ),
              if (_loading)
                Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
                ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => _edgeDragDistance = 0,
                  onHorizontalDragUpdate: (details) {
                    _edgeDragDistance += details.primaryDelta ?? 0;
                  },
                  onHorizontalDragEnd: (_) {
                    if (_edgeDragDistance >= 72) unawaited(_back());
                    _edgeDragDistance = 0;
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
