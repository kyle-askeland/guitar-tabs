import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../models/tab_text.dart';
import '../storage/song_store.dart';
import '../widgets/fret_pad.dart';
import '../widgets/tab_grid.dart';

// Characters that can follow a fret number and be followed by another
// (5h7, 7b9r7, 5/7); a digit typed after one of these extends the cell.
const _connectors = 'hpbrt/\\~';
const _maxCellLength = 8;

class _Cursor {
  int section, line, col, str;
  _Cursor(this.section, this.line, this.col, this.str);
}

class EditorScreen extends StatefulWidget {
  final String id;
  const EditorScreen({super.key, required this.id});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Song? song;
  String? loadError;
  _Cursor? cursor;
  bool playView = false;
  bool dirty = false;
  Timer? saveTimer;
  DateTime lastKey = DateTime(0);
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    store.fetch(widget.id).then(
      (s) => setState(() {
        song = s;
        playView = !s.mine; // read-only for songs this browser doesn't own
      }),
      onError: (e) => setState(() => loadError = '$e'),
    );
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    if (dirty) store.save(song!); // flush pending autosave on exit
    focus.dispose();
    super.dispose();
  }

  Line get _line => song!.sections[cursor!.section].lines[cursor!.line];

  /// Every mutation goes through here: rebuild + debounced autosave (SPECS §4).
  void _touch() {
    setState(() => dirty = true);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    dirty = false;
    try {
      await store.save(song!);
      if (mounted) setState(() {});
    } catch (e) {
      dirty = true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  // ---- editing ----

  /// Applies typed/tapped input to the cell under the cursor. `text` is a
  /// single key or a whole fret-pad token; digits within the typing window or
  /// after a connector (5h -> 5h7) extend the cell, otherwise they replace it.
  void _input(String text) {
    if (cursor == null) return;
    final line = _line;
    final existing = line.cellAt(cursor!.col, cursor!.str)?.fret ?? '';
    final now = DateTime.now();
    String next;
    if (RegExp(r'^\d+$').hasMatch(text)) {
      final chained = existing.isNotEmpty &&
          (_connectors.contains(existing[existing.length - 1]) ||
              now.difference(lastKey).inMilliseconds < 800);
      next = chained ? existing + text : text;
    } else if (text == 'x') {
      next = 'x';
    } else if (_connectors.contains(text)) {
      if (existing.isEmpty) return; // techniques modify a fret
      next = existing + text;
    } else {
      return;
    }
    lastKey = now;
    if (next.length > _maxCellLength) return;
    line.setCell(cursor!.col, cursor!.str, next);
    _touch();
  }

  void _clearCell() {
    if (cursor == null) return;
    _line.setCell(cursor!.col, cursor!.str, '');
    _touch();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || cursor == null || playView) {
      return KeyEventResult.ignored;
    }
    final c = cursor!;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (c.col > 0) c.col--;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.space:
        if (c.col < _line.length - 1) c.col++;
      case LogicalKeyboardKey.arrowUp:
        if (c.str < 5) c.str++; // up on screen = higher string
      case LogicalKeyboardKey.arrowDown:
        if (c.str > 0) c.str--;
      case LogicalKeyboardKey.backspace:
      case LogicalKeyboardKey.delete:
        _clearCell();
        return KeyEventResult.handled;
      default:
        final ch = event.character;
        if (ch == '|') {
          final bars = _line.barlines;
          bars.contains(c.col) ? bars.remove(c.col) : (bars..add(c.col)..sort());
          _touch();
          return KeyEventResult.handled;
        }
        if (ch != null && ch.isNotEmpty) {
          _input(ch);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
    lastKey = DateTime(0); // movement ends the multi-digit typing window
    setState(() {});
    return KeyEventResult.handled;
  }

  // ---- structure ops (clear the cursor: its indexes may no longer exist) ----

  void _structural(VoidCallback op) {
    cursor = null;
    op();
    _touch();
  }

  Future<void> _addSection() async {
    final name = await _prompt('Section name', 'Verse');
    if (name != null && name.isNotEmpty) {
      _structural(() => song!.sections.add(Section(name: name)));
    }
  }

  Future<String?> _prompt(String title, String hint, [String initial = '']) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _editSongSettings() async {
    final s = song!;
    final title = TextEditingController(text: s.title);
    final artist = TextEditingController(text: s.artist);
    final capo = TextEditingController(text: '${s.capo}');
    final tuning = TextEditingController(text: s.tuning.join(' '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Song settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: artist, decoration: const InputDecoration(labelText: 'Artist')),
          TextField(controller: capo, decoration: const InputDecoration(labelText: 'Capo')),
          TextField(
            controller: tuning,
            decoration: const InputDecoration(
              labelText: 'Tuning (low to high)',
              hintText: 'E A D G B E',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final notes = tuning.text.trim().split(RegExp(r'\s+'));
    setState(() {
      s.title = title.text.trim().isEmpty ? s.title : title.text.trim();
      s.artist = artist.text.trim();
      s.capo = int.tryParse(capo.text) ?? s.capo;
      if (notes.length == 6) s.tuning = notes;
    });
    _touch();
  }

  Future<void> _deleteSong() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${song!.title}"?'),
        content: const Text('This is permanent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    saveTimer?.cancel();
    dirty = false;
    await store.delete(song!.songId);
    if (mounted) context.go('/');
  }

  void _exportText() {
    final text = renderSong(song!);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export as text'),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(text, style: tabTextStyle),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (loadError != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(loadError!)));
    }
    final s = song;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          if (dirty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: Text('saving…')),
            ),
          IconButton(
            icon: const Icon(Icons.text_snippet_outlined),
            tooltip: 'Export as text',
            onPressed: _exportText,
          ),
          if (s.mine)
            IconButton(
              icon: Icon(playView ? Icons.edit : Icons.play_arrow),
              tooltip: playView ? 'Edit' : 'Play view',
              onPressed: () => setState(() {
                playView = !playView;
                cursor = null;
              }),
            ),
          if (s.mine)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'settings' ? _editSongSettings() : _deleteSong(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'settings', child: Text('Song settings')),
                PopupMenuItem(value: 'delete', child: Text('Delete song')),
              ],
            ),
        ],
      ),
      body: playView ? _buildPlayView(s) : _buildEditor(s, narrow),
    );
  }

  Widget _buildPlayView(Song s) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            renderSong(s),
            style: tabTextStyle.copyWith(fontSize: 18),
          ),
        ),
      );

  Widget _buildEditor(Song s, bool narrow) {
    return Focus(
      focusNode: focus,
      onKeyEvent: _onKey,
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (var si = 0; si < s.sections.length; si++) ..._section(s, si),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addSection,
                  icon: const Icon(Icons.add),
                  label: const Text('Add section'),
                ),
              ),
            ],
          ),
        ),
        if (narrow && cursor != null)
          FretPad(onInput: _input, onClear: _clearCell),
      ]),
    );
  }

  List<Widget> _section(Song s, int si) {
    final section = s.sections[si];
    return [
      Row(children: [
        TextButton(
          onPressed: () async {
            final name = await _prompt('Rename section', '', section.name);
            if (name != null && name.isNotEmpty) {
              setState(() => section.name = name);
              _touch();
            }
          },
          child: Text(section.name, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          icon: const Icon(Icons.playlist_add, size: 20),
          tooltip: 'Add line',
          onPressed: () => _structural(() => section.lines.add(Line())),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Delete section',
          onPressed: () => _structural(() => s.sections.removeAt(si)),
        ),
      ]),
      for (var li = 0; li < section.lines.length; li++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TabGrid(
                line: section.lines[li],
                tuning: s.tuning,
                cursorCol: _at(si, li) ? cursor!.col : null,
                cursorStr: _at(si, li) ? cursor!.str : null,
                onTapCell: (col, str) {
                  setState(() => cursor = _Cursor(si, li, col, str));
                  focus.requestFocus();
                },
              ),
            ),
            PopupMenuButton<String>(
              iconSize: 18,
              onSelected: (v) {
                final line = section.lines[li];
                switch (v) {
                  case 'grow':
                    _structural(() => line.length += 8);
                  case 'shrink':
                    if (line.length > 8) {
                      _structural(() {
                        line.length -= 8;
                        line.cells.removeWhere((c) => c.col >= line.length);
                        line.barlines.removeWhere((b) => b >= line.length);
                      });
                    }
                  case 'delete':
                    _structural(() => section.lines.removeAt(li));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'grow', child: Text('Add 8 columns')),
                PopupMenuItem(value: 'shrink', child: Text('Remove 8 columns')),
                PopupMenuItem(value: 'delete', child: Text('Delete line')),
              ],
            ),
          ]),
        ),
    ];
  }

  bool _at(int si, int li) =>
      cursor != null && cursor!.section == si && cursor!.line == li;
}
