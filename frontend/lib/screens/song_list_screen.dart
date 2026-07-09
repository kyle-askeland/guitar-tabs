import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../storage/song_store.dart';

class SongListScreen extends StatefulWidget {
  const SongListScreen({super.key});

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  late Future<List<SongSummary>> songs = store.list();
  bool mineOnly = true;

  void _reload() => setState(() => songs = store.list());

  Future<void> _newSong() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New song'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Title'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final song = await store.create(title);
    if (mounted) {
      await context.push('/songs/${song.songId}');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guitar Tabs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSong,
        icon: const Icon(Icons.add),
        label: const Text('New Song'),
      ),
      body: FutureBuilder(
        future: songs,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final visible = [
            for (final s in snapshot.data!)
              if (!mineOnly || s.mine) s
          ];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Mine')),
                  ButtonSegment(value: false, label: Text('All')),
                ],
                selected: {mineOnly},
                onSelectionChanged: (v) => setState(() => mineOnly = v.first),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No songs yet — create one!'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final s = visible[i];
                        return ListTile(
                          title: Text(s.title),
                          subtitle: Text([
                            if (s.artist.isNotEmpty) s.artist,
                            s.updatedAt.split('T').first,
                          ].join(' · ')),
                          onTap: () async {
                            await context.push('/songs/${s.songId}');
                            _reload();
                          },
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}
