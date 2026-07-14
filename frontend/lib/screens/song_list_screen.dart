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
  final search = TextEditingController();
  bool mineOnly = true;
  String query = '';

  @override
  void initState() {
    super.initState();
    // Saves, renames, and deletes anywhere in the app land here immediately.
    songsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    songsChanged.removeListener(_reload);
    search.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final next = store.list();
    setState(() {
      songs = next; // a block body: setState rejects a closure returning a Future
    });
  }

  /// Search runs on submit, never per keystroke — the list is fetched once
  /// and filtered here, so typing costs no Lambda invocations.
  void _runSearch() => setState(() => query = search.text.trim().toLowerCase());

  /// Creates the song immediately — no title prompt. The title defaults to
  /// the current timestamp (unique, no collisions) and is renamed later via
  /// song settings in the editor.
  Future<void> _newSong() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final title =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final song = await store.create(title);
    if (mounted) context.push('/songs/${song.songId}');
  }

  Future<void> _rename(SongSummary s) async {
    final controller = TextEditingController(text: s.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename song'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || title == s.title) return;
    final song = await store.fetch(s.songId);
    song.title = title;
    await store.save(song);
  }

  Future<void> _delete(SongSummary s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete song?'),
        content: Text('Are you sure you want to delete "${s.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    await store.delete(s.songId);
  }

  bool _matches(SongSummary s) =>
      (!mineOnly || s.mine) &&
      (query.isEmpty ||
          s.title.toLowerCase().contains(query) ||
          s.artist.toLowerCase().contains(query));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TabStash'),
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
              if (_matches(s)) s
          ];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Mine')),
                  ButtonSegment(value: false, label: Text('All')),
                ],
                selected: {mineOnly},
                onSelectionChanged: (v) => setState(() => mineOnly = v.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search titles and artists',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear',
                              onPressed: () {
                                search.clear();
                                _runSearch();
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _runSearch, child: const Text('Search')),
              ]),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(query.isEmpty
                          ? 'No songs yet — create one!'
                          : 'No songs match "$query"'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final s = visible[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          color: Theme.of(context).colorScheme.surface,
                          child: ListTile(
                            title: Text(s.title),
                            subtitle: Text([
                              if (s.artist.isNotEmpty) s.artist,
                              s.updatedAt.split('T').first,
                            ].join(' · ')),
                            trailing: s.mine
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      tooltip: 'Rename',
                                      onPressed: () => _rename(s),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      tooltip: 'Delete',
                                      onPressed: () => _delete(s),
                                    ),
                                  ])
                                : null,
                            onTap: () => context.push('/songs/${s.songId}'),
                          ),
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
