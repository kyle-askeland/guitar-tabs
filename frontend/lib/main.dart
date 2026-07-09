import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/editor_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/song_list_screen.dart';

void main() => runApp(const App());

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
    return MaterialApp.router(
      title: 'Guitar Tabs',
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      routerConfig: _router,
    );
  }
}
