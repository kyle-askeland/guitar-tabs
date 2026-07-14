import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../models/tab_import.dart';
import '../storage/song_store.dart';
import '../widgets/chord_dialog.dart';
import '../widgets/fretboard_pad.dart';
import '../widgets/notes_card.dart';
import '../widgets/tab_staff.dart';
import '../widgets/wood_background.dart';

// Characters that can follow a fret number and be followed by another
// (5h7, 7b9r7, 5/7); a digit typed after one of these extends the cell.
const _connectors = 'hpbrt/\\~';
const _maxCellLength = 8;

final _noteRe = RegExp(r'^[A-Ga-g](#|b)?$');

/// null = valid. Requires exactly six space-separated note names.
String? _validateTuning(String text) {
  final notes = text.trim().split(RegExp(r'\s+'));
  if (notes.length != 6 || notes.any((n) => n.isEmpty)) {
    return 'Enter exactly 6 notes, space separated';
  }
  if (notes.any((n) => !_noteRe.hasMatch(n))) {
    return 'Each note must be A-G, optionally # or b (e.g. E A D G B E)';
  }
  return null;
}

/// null = valid. Requires a whole number in a sane measure-length range.
String? _validateBeats(String text) {
  final n = int.tryParse(text.trim());
  if (n == null || n < 1 || n > 32) return 'Enter a whole number from 1 to 32';
  return null;
}

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
  bool saving = false;
  DateTime lastKey = DateTime(0);
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    store.fetch(widget.id).then(
      (s) => setState(() {
        song = s;
        final blank = s.sections.isEmpty;
        // Existing tabs open read-only; a brand-new song has nothing to
        // show yet, so go straight into editing it.
        playView = !(s.mine && blank);
        // A fresh song opens with an empty line ready to tap into.
        if (s.mine && blank) s.sections.add(Section(name: ''));
      }),
      onError: (e) => setState(() => loadError = '$e'),
    );
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  Line get _line => song!.sections[cursor!.section].lines[cursor!.line];

  /// Every mutation goes through here: rebuild + mark unsaved. Nothing hits
  /// the store until the user presses Save (keeps Lambda/DB writes rare).
  void _touch() {
    setState(() => dirty = true);
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await store.save(song!);
      if (mounted) setState(() => dirty = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Back navigation with an unsaved-changes guard: save, discard, or stay.
  Future<void> _goBack() async {
    void leave() =>
        context.canPop() ? context.pop() : context.go('/');
    if (!dirty) {
      leave();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('"${song!.title}" has changes that haven\'t been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save & exit')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'save') {
      await _save();
      if (!mounted || dirty) return; // save failed — stay
    }
    leave();
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

  /// Fretboard pad input: toggles `fret` on `str` in the cursor's column.
  /// After a connector (5h + tap 7 → 5h7) the fret extends the cell instead.
  void _padFret(int str, int fret) {
    if (cursor == null) return;
    final existing = _line.cellAt(cursor!.col, str)?.fret ?? '';
    final String next;
    if (existing == '$fret') {
      next = ''; // tapping the same fret again removes the note
    } else if (existing.isNotEmpty &&
        _connectors.contains(existing[existing.length - 1])) {
      next = '$existing$fret';
    } else {
      next = '$fret';
    }
    if (next.length > _maxCellLength) return;
    cursor!.str = str;
    lastKey = DateTime(0);
    _line.setCell(cursor!.col, str, next);
    _touch();
  }

  /// Tapping the chord row picks a chord and, on "Fill tab", stamps its
  /// shape into the six strings of that column.
  Future<void> _editChord(Line line, int col) async {
    final choice = await showChordDialog(context, existing: line.chordAt(col));
    if (choice == null) return;
    line.setChord(col, choice.name);
    final frets = choice.frets;
    if (frets != null) {
      for (var str = 0; str < 6; str++) {
        line.setCell(col, str, frets[str]?.toString() ?? '');
      }
    }
    _touch();
  }

  Future<void> _editLyric(Line line, int col) async {
    final text =
        await _prompt('Lyrics here', 'and so it goes…', line.lyricAt(col) ?? '');
    if (text == null) return;
    line.setLyric(col, text);
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

  /// Appends a fresh line (2 measures) to the song. Sections exist only in
  /// the data model (and for imported tabs that carry names); the UI is a
  /// flat list of lines.
  void _addLine() {
    _structural(() {
      if (song!.sections.isEmpty) song!.sections.add(Section(name: '', lines: []));
      final length = defaultLineLength(song!.beatsPerMeasure);
      song!.sections.last.lines.add(
        Line(length: length, barlines: defaultBarlines(length, song!.beatsPerMeasure)),
      );
    });
  }

  /// Appends one measure to the last line, so a tab can be built up one
  /// click at a time instead of committing to a whole line upfront. Starts
  /// the first line (at a single measure) if the song has none yet.
  void _addMeasure() {
    _structural(() {
      if (song!.sections.isEmpty) song!.sections.add(Section(name: '', lines: []));
      final lines = song!.sections.last.lines;
      final cols = measureCols(song!.beatsPerMeasure);
      if (lines.isEmpty) {
        lines.add(Line(length: cols, barlines: []));
      } else {
        lines.last.addMeasure(cols);
      }
    });
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
    final beats = TextEditingController(text: '${s.beatsPerMeasure}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final tuningError = _validateTuning(tuning.text);
        final beatsError = _validateBeats(beats.text);
        return AlertDialog(
          title: const Text('Song settings'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: artist, decoration: const InputDecoration(labelText: 'Artist')),
              TextField(
                controller: capo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capo'),
              ),
              TextField(
                controller: tuning,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tuning (low to high)',
                  hintText: 'E A D G B E',
                  errorText: tuningError,
                ),
              ),
              TextField(
                controller: beats,
                keyboardType: TextInputType.number,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Beats per measure',
                  hintText: '4',
                  errorText: beatsError,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: tuningError == null && beatsError == null
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
    if (saved != true) return;
    final newBeats = int.parse(beats.text.trim());
    final oldBeats = s.beatsPerMeasure;
    if (newBeats != oldBeats) {
      final losses = [for (final sec in s.sections) ...sec.lines]
          .fold(0, (n, l) => n + l.remeasureLosses(oldBeats, newBeats));
      if (losses > 0) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Beats per measure'),
            content: Text(
              'Changing to $newBeats beats per measure will delete $losses '
              'note${losses == 1 ? '' : 's'}/chord${losses == 1 ? '' : 's'}/'
              'lyric${losses == 1 ? '' : 's'} that no longer fit within a '
              'measure. Continue?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
            ],
          ),
        );
        if (!mounted || proceed != true) return;
      }
    }
    setState(() {
      s.title = title.text.trim().isEmpty ? s.title : title.text.trim();
      s.artist = artist.text.trim();
      s.capo = int.tryParse(capo.text) ?? s.capo;
      s.tuning = tuning.text.trim().split(RegExp(r'\s+'));
      if (newBeats != oldBeats) {
        s.beatsPerMeasure = newBeats;
        // Re-lay every line onto the new measure grid (SPECS §3): each
        // column keeps its (measure, offset) pair, just wider or narrower —
        // see Line.remeasure. Anything that no longer fits was already
        // confirmed above via remeasureLosses.
        for (final section in s.sections) {
          for (final line in section.lines) {
            line.remeasure(oldBeats, newBeats);
          }
        }
      }
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
    dirty = false;
    await store.delete(song!.songId);
    if (mounted) context.go('/');
  }

  Future<void> _renameSong() async {
    final text = await _prompt('Song title', '', song!.title);
    if (text == null || text.isEmpty || text == song!.title) return;
    song!.title = text;
    _touch();
  }

  Future<void> _editNotes() async {
    final controller = TextEditingController(text: song!.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes & links'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Practice notes, tutorial links…\nURLs become tappable.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => song!.notes = controller.text.trim());
    _touch();
  }

  Future<void> _importTab() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import tab'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 12,
            style: tabTextStyle.copyWith(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Paste an ASCII tab. 6-line blocks, [Section] headers,\n'
                  'chord rows, and lyric lines are picked up automatically.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    final imported = parseTab(controller.text);
    if (imported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No tab found — expected 6-line blocks like e|---3---|')));
      }
      return;
    }
    _structural(() => song!.sections.addAll(imported));
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
        leading: BackButton(onPressed: _goBack),
        // Tapping the title renames the song (owners only).
        title: s.mine
            ? InkWell(
                onTap: _renameSong,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(s.title, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 16),
                  ]),
                ),
              )
            : Text(s.title),
        actions: [
          if (s.mine)
            IconButton(
              icon: Icon(playView ? Icons.edit : Icons.play_arrow, size: 28),
              tooltip: playView ? 'Edit' : 'Play view',
              onPressed: () => setState(() {
                playView = !playView;
                cursor = null;
              }),
            ),
          if (s.mine)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'import' => _importTab(),
                'settings' => _editSongSettings(),
                _ => _deleteSong(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'import', child: Text('Import tab (paste)')),
                PopupMenuItem(value: 'settings', child: Text('Song settings')),
                PopupMenuItem(value: 'delete', child: Text('Delete song')),
              ],
            ),
        ],
      ),
      body: playView ? _buildPlayView(s) : _buildEditor(s, narrow),
    );
  }

  /// Tab staves need an opaque backdrop — the fret numbers knock the string
  /// lines out behind them, and the wood grain would show through.
  Widget _card(Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Theme.of(context).colorScheme.surface,
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      );

  Widget _buildPlayView(Song s) {
    final nonStandard = s.tuning.join(' ') != standardTuning.join(' ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NotesCard(notes: s.notes),
        if (s.capo > 0 || nonStandard)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              [
                if (s.capo > 0) 'Capo ${s.capo}',
                if (nonStandard) 'Tuning ${s.tuning.join(' ')}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final section in s.sections) ...[
          if (section.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(section.name,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          for (final line in section.lines)
            _card(TabStaff(line: line, tuning: s.tuning, scale: 1.15)),
        ],
      ],
    );
  }

  Widget _buildEditor(Song s, bool narrow) {
    return Focus(
      focusNode: focus,
      onKeyEvent: _onKey,
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              NotesCard(notes: s.notes, onEdit: _editNotes),
              for (var si = 0; si < s.sections.length; si++) ..._section(s, si),
              Wrap(spacing: 8, runSpacing: 8, children: [
                WoodLegibleButton(
                  onPressed: _addMeasure,
                  icon: Icons.add,
                  label: 'Add measure',
                ),
                WoodLegibleButton(
                  onPressed: _addLine,
                  icon: Icons.playlist_add,
                  label: 'Add line',
                ),
              ]),
            ],
          ),
        ),
        if (s.mine) _saveBar(),
        if (narrow && cursor != null)
          FretboardPad(
            column: [
              for (var str = 0; str < 6; str++)
                _line.cellAt(cursor!.col, str)?.fret ?? ''
            ],
            tuning: s.tuning,
            onFret: _padFret,
            onSymbol: _input,
            onClear: _clearCell,
            onPrev: () => setState(() {
              if (cursor!.col > 0) cursor!.col--;
            }),
            onNext: () => setState(() {
              if (cursor!.col < _line.length - 1) cursor!.col++;
            }),
          ),
      ]),
    );
  }

  /// Nothing is persisted until this is pressed, so it is the biggest,
  /// loudest thing on the screen — and it stays put (showing "Saved") rather
  /// than vanishing, so there's never a doubt about where the changes went.
  Widget _saveBar() {
    final clean = !dirty && !saving;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: FilledButton.icon(
          onPressed: clean ? null : _save,
          icon: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(clean ? Icons.check : Icons.save, size: 26),
          label: Text(
            saving ? 'Saving…' : (clean ? 'Saved' : 'Save changes'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  List<Widget> _section(Song s, int si) {
    final section = s.sections[si];
    return [
      // Section names aren't part of the editing flow; imported tabs that
      // carry one ([Intro], Verse…) still show it as a small label.
      if (section.name.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(section.name, style: Theme.of(context).textTheme.titleSmall),
        ),
      for (var li = 0; li < section.lines.length; li++)
        _card(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TabStaff(
              line: section.lines[li],
              tuning: s.tuning,
              editable: true,
              cursorCol: _at(si, li) ? cursor!.col : null,
              cursorStr: _at(si, li) ? cursor!.str : null,
              onTapCell: (col, str) {
                setState(() => cursor = _Cursor(si, li, col, str));
                focus.requestFocus();
              },
              onTapChord: (col) => _editChord(section.lines[li], col),
              onTapLyric: (col) => _editLyric(section.lines[li], col),
            ),
          ),
          PopupMenuButton<String>(
            iconSize: 18,
            onSelected: (v) {
              final line = section.lines[li];
              final cols = measureCols(s.beatsPerMeasure);
              switch (v) {
                case 'grow':
                  _structural(() => line.addMeasure(cols));
                case 'shrink':
                  if (line.length > cols) {
                    _structural(() => line.removeMeasure(cols));
                  }
                case 'delete':
                  _structural(() {
                    section.lines.removeAt(li);
                    if (section.lines.isEmpty) s.sections.removeAt(si);
                  });
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'grow', child: Text('Add measure')),
              PopupMenuItem(value: 'shrink', child: Text('Remove measure')),
              PopupMenuItem(value: 'delete', child: Text('Delete line')),
            ],
          ),
        ])),
    ];
  }

  bool _at(int si, int li) =>
      cursor != null && cursor!.section == si && cursor!.line == li;
}
