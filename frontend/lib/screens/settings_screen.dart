import 'package:flutter/material.dart';

import '../storage/app_theme.dart';
import '../storage/owner_token.dart';
import '../storage/song_store.dart';

/// Shows the anonymous owner token (SPECS §7) so it can be copied to another
/// device; pasting a token here transfers this browser's identity.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    getOwnerToken().then((t) => setState(() => controller.text = t));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {darkModeNotifier.value},
            onSelectionChanged: (v) => setDarkMode(v.first),
          ),
          const SizedBox(height: 24),
          Text('Owner token', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'This token is your identity: it grants edit and delete rights to '
            'the songs you created. To own the same songs on another device, '
            'copy it there and save. Clearing browser data loses it.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await setOwnerToken(controller.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Token saved')));
              }
            },
            child: const Text('Save token'),
          ),
          const SizedBox(height: 24),
          Text(
            apiUrl.isEmpty
                ? 'Storage: browser localStorage (no API configured)'
                : 'Storage: $apiUrl',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}
