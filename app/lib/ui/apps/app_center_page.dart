import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

import '../shell/page_frame.dart';
import 'paw_app_page.dart';

/// Native application entry point. More independent systems can be added here.
class AppCenterPage extends StatelessWidget {
  const AppCenterPage({super.key});

  @override
  Widget build(BuildContext context) => AppPage.list(
    title: context.l10n.pawApps,
    children: [
      ListTile(
        key: const ValueKey('paw-app-entry'),
        leading: const Icon(Icons.candlestick_chart),
        title: Text(context.l10n.pawTrading),
        subtitle: Text(context.l10n.pawDescription),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PawAppPage())),
      ),
    ],
  );
}
