import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/editor_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/song_list_screen.dart';
import 'storage/app_theme.dart';
import 'widgets/wood_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadTheme();
  runApp(const App());
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const SongListScreen()),
  GoRoute(
    path: '/songs/:id',
    builder: (_, state) => EditorScreen(id: state.pathParameters['id']!),
  ),
  GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
]);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: darkModeNotifier,
      builder: (context, dark, _) => MaterialApp.router(
        title: 'TabStash',
        theme: themeFor(dark),
        routerConfig: _router,
        // Scaffolds are transparent (see app_theme.dart); the wood is painted
        // once here, behind every screen.
        builder: (context, child) => WoodBackground(dark: dark, child: child!),
      ),
    );
  }
}
