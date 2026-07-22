import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/lyrics_lookup.dart';
import '../models/song.dart';
import '../models/tab_import.dart';
import '../storage/song_store.dart';
import '../widgets/chord_dialog.dart';
import '../widgets/fretboard_pad.dart';
import '../widgets/legend_dialog.dart';
import '../widgets/notes_card.dart';
import '../widgets/tab_staff.dart';
import '../widgets/wood_background.dart';

// Characters that can follow a fret number and be followed by another
// (5h7, 7b9r7, 5/7); a digit typed after one of these extends the cell.
const _connectors = 'hpbrt/\\~';
const _maxCellLength = 8;

/// Width (in columns) given to a lyric row with no words — still wide
/// enough for a stray instrumental chord between verses, without paying for
/// a full [defaultLineLength].
const _blankChordLineCols = 4;

/// One chords-mode line for a row of plain lyrics: a blank row becomes a
/// short placeholder, and a populated row gets one column per word so a
/// chord tapped above a word lands exactly on it — not on an arbitrary slot
/// in a fixed-width grid that had no relationship to where the words fell.
/// Shared by [_EditorScreenState._addChordsParagraph] (typed/pasted text)
/// and [_EditorScreenState._populateFromLyrics] (lyrics.ovh lookup).
Line _chordsLineFromLyricRow(String row) {
  final words =
      row.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return Line(
        mode: 'chords', length: _blankChordLineCols, barlines: const []);
  }
  return Line(
    mode: 'chords',
    length: words.length,
    barlines: const [],
    lyrics: [
      for (var i = 0; i < words.length; i++) LyricMark(col: i, text: words[i])
    ],
  );
}

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

/// In-memory clipboard for "Copy chords" / "Paste chords": just the
/// chord-related layers (chords, strums, and — for a tab-mode source —
/// fretboard cells), never lyrics. Lets a chord pattern already tapped into
/// one line be applied to other lines that already have their own lyrics,
/// which [_EditorScreenState._duplicateLine] can't do since it always
/// inserts a brand new line rather than merging into an existing one.
class _ChordClipboard {
  final List<ChordMark> chords;
  final List<StrumMark> strums;
  final List<Cell> cells;
  _ChordClipboard(this.chords, this.strums, this.cells);
}

/// Result of [_EditorScreenState._startSongDialog]: either pasted text
/// ready to populate directly, or an artist/title pair to look up.
class _LyricsEntry {
  final String? pastedText;
  final String? artist;
  final String? title;
  _LyricsEntry.paste(this.pastedText)
      : artist = null,
        title = null;
  _LyricsEntry.lookup(this.artist, this.title) : pastedText = null;
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
  bool lookingUpLyrics = false;
  DateTime lastKey = DateTime(0);
  final focus = FocusNode();
  _ChordClipboard? _chordClipboard;

  // ---- undo: a bounded stack of pre-mutation snapshots, keyed off _touch()
  // (the single funnel every edit path already runs through). See _touch().
  static const _maxUndo = 150;
  final List<String> _undoStack = [];
  String? _lastSnapshot;

  // ---- play view: autoscroll + zoom (session-only, not persisted — scroll
  // speed is song-tempo-dependent and zoom is a cheap one-tap redo).
  final _playScroll = ScrollController();
  bool _autoScrolling = false;
  double _scrollSpeed = 40; // px/sec
  double _playZoom = 1.15; // was a hardcoded TabStaff scale
  Timer? _autoTimer;

  // ---- edit view zoom (session-only): a phone screen only fits so many
  // columns before every line needs a horizontal scroll to work in: shrinking
  // column width buys more of the line visible at once, at the cost of size.
  double _editZoom = 1;

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
            // A fresh song opens with an empty line ready to tap into. Chords
            // mode by default: paste-lyrics-then-tap-chords is the common case
            // (see docs/ARCHITECTURE.md); dropping into tab is the explicit
            // "+ Tab line" action below.
            if (s.mine && blank) {
              s.sections.add(Section(name: '', lines: [Line(mode: 'chords')]));
              // Offer the fast path in on top of that placeholder: look up
              // lyrics by artist/title, or paste them — either replaces the
              // placeholder outright (docs/ARCHITECTURE.md's "Starting a new
              // song"), minus the library-search step that was once envisioned.
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => mounted ? _startSongDialog() : null);
            }
            // Baseline for the undo stack: the first _touch() diffs against this.
            _lastSnapshot = jsonEncode(s.toJson());
          }),
          onError: (e) => setState(() => loadError = '$e'),
        );
  }

  @override
  void dispose() {
    focus.dispose();
    _playScroll.dispose();
    _autoTimer?.cancel();
    super.dispose();
  }

  /// Stops autoscroll without touching `dirty`/undo state — called on pause,
  /// on leaving play view, and once the staff scrolls to its end.
  void _stopAutoScroll() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoScrolling = false;
  }

  static const _autoScrollTick = Duration(milliseconds: 30);

  void _toggleAutoScroll() {
    if (_autoScrolling) {
      setState(_stopAutoScroll);
      return;
    }
    _autoTimer = Timer.periodic(_autoScrollTick, (_) {
      if (!_playScroll.hasClients) return;
      final perTick = _scrollSpeed * _autoScrollTick.inMilliseconds / 1000;
      final max = _playScroll.position.maxScrollExtent;
      final next = (_playScroll.offset + perTick).clamp(0.0, max);
      _playScroll.jumpTo(next);
      if (next >= max) setState(_stopAutoScroll);
    });
    setState(() => _autoScrolling = true);
  }

  Line get _line => song!.sections[cursor!.section].lines[cursor!.line];

  /// Every mutation goes through here: rebuild + mark unsaved. Nothing hits
  /// the store until the user presses Save (keeps Lambda/DB writes rare).
  ///
  /// Also the undo funnel: since this always runs synchronously right after
  /// whatever just mutated `song`, and is the sole writer of `dirty`,
  /// `_lastSnapshot` going in is always exactly the state as of the end of
  /// the *previous* mutation — i.e. the correct pre-mutation snapshot to
  /// restore if the user undoes this edit.
  void _touch() {
    if (_lastSnapshot != null) {
      _undoStack.add(_lastSnapshot!);
      if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    }
    _lastSnapshot = jsonEncode(song!.toJson());
    setState(() => dirty = true);
  }

  /// Steps back one edit. No redo — undo is meant as an "oops" button, not a
  /// history browser.
  void _undo() {
    if (_undoStack.isEmpty) return;
    final prev = _undoStack.removeLast();
    cursor = null; // indexes may no longer exist after the restore
    song = Song.fromJson(jsonDecode(prev));
    _lastSnapshot = prev;
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
    void leave() => context.canPop() ? context.pop() : context.go('/');
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
  /// shape into the six strings of that column. On a chords-mode line, the
  /// same dialog also offers "Add slot after" / "Remove slot" — a normal
  /// tap/click that works identically on phone and desktop, rather than a
  /// separate gesture.
  Future<void> _editChord(Line line, int col) async {
    final chordsMode = line.mode == 'chords';
    final emptySlot = chordsMode &&
        line.chordAt(col) == null &&
        line.lyricAt(col) == null &&
        line.strumAt(col) == null;
    final choice = await showChordDialog(
      context,
      existing: line.chordAt(col),
      onInsertSlot:
          chordsMode ? () => _structural(() => line.insertColumn(col + 1)) : null,
      onRemoveSlot:
          emptySlot ? () => _structural(() => line.removeColumn(col)) : null,
    );
    if (choice == null) return;
    line.setChord(col, choice.name);
    final frets = choice.frets;
    if (frets != null) {
      for (var str = 0; str < 6; str++) {
        // null = string not played in this shape — stamp it as an explicit
        // mute (`x`, docs/ARCHITECTURE.md's notation standard) rather than
        // leaving the cell blank.
        line.setCell(col, str, frets[str]?.toString() ?? 'x');
      }
    }
    _touch();
  }

  /// Tapping the strum row cycles none -> down -> up -> none — quick enough
  /// for tapping out a whole strumming pattern without a dialog per column.
  void _cycleStrum(Line line, int col) {
    final current = line.strumAt(col);
    final next = current == null ? 'D' : (current == 'D' ? 'U' : null);
    line.setStrum(col, next ?? '');
    _touch();
  }

  /// Tapping the lyric row edits this column's word. Splitting the text
  /// with a space *or* a dash — "some thing", "every-thing" — inserts a
  /// fresh column right after the previous part for each extra piece (see
  /// [Line.insertColumn]), so a split lands immediately next to the word it
  /// came from and everything later in the line shifts along to make room.
  /// An earlier version tried to find or grow a slot for the extra piece
  /// without inserting, which either overwrote a different, already-there
  /// word or dumped the new piece off at the far end of the line — always
  /// inserting is what makes a split land exactly where you split it.
  Future<void> _editLyric(Line line, int col) async {
    final text = await _prompt('Lyrics here',
        'and so it goes… (space or - splits into its own column)',
        line.lyricAt(col) ?? '');
    if (text == null) return;
    final words = text
        .trim()
        .split(RegExp(r'[\s-]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    line.setLyric(col, words.isEmpty ? '' : words.first);
    for (var i = 1; i < words.length; i++) {
      line.insertColumn(col + i);
      line.setLyric(col + i, words[i]);
    }
    _touch();
  }


  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || playView) return KeyEventResult.ignored;
    // Checked before the cursor guard below: _structural() (delete line,
    // add/remove measure, mode-flip, import...) always nulls the cursor
    // before mutating, so undo must not depend on one being set.
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _undo();
      return KeyEventResult.handled;
    }
    if (cursor == null) return KeyEventResult.ignored;
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
          bars.contains(c.col)
              ? bars.remove(c.col)
              : (bars
                ..add(c.col)
                ..sort());
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

  /// Appends a blank tab-mode line (1 measure) to a section: the fretboard,
  /// unchanged — for a riff that needs real frets (see docs/ARCHITECTURE.md).
  void _addTabLine(int si) {
    _structural(() {
      final length = defaultLineLength(song!.beatsPerMeasure);
      song!.sections[si].lines.add(
        Line(
          length: length,
          barlines: defaultBarlines(length, song!.beatsPerMeasure),
          mode: 'tab',
        ),
      );
    });
  }

  /// Inserts a blank line directly above an existing one, matching that
  /// line's mode (tab or chords) — the counterpart to [_addTabLine] /
  /// [_addChordsParagraph], which only ever append to the end of a section.
  void _insertLineAbove(int si, int li) {
    _structural(() {
      final length = defaultLineLength(song!.beatsPerMeasure);
      final mode = song!.sections[si].lines[li].mode;
      final line = mode == 'tab'
          ? Line(
              length: length,
              barlines: defaultBarlines(length, song!.beatsPerMeasure),
              mode: 'tab',
            )
          : Line(mode: 'chords', length: length, barlines: const []);
      song!.sections[si].lines.insert(li, line);
    });
  }

  /// Inserts a deep copy of a line directly below it — the fastest way to
  /// repeat a riff or verse without re-entering every cell.
  void _duplicateLine(int si, int li) {
    _structural(() {
      final line = song!.sections[si].lines[li];
      song!.sections[si].lines.insert(li + 1, Line.fromJson(line.toJson()));
    });
  }

  /// Copies a line's chords, strums, and (if it's a tab-mode line) fretboard
  /// cells onto the in-memory clipboard for [_pasteChords] — never lyrics,
  /// so the pattern can be applied to lines that already have their own.
  void _copyChords(Line line) {
    _chordClipboard = _ChordClipboard(
      [for (final c in line.chords) ChordMark(col: c.col, name: c.name)],
      [for (final s in line.strums) StrumMark(col: s.col, dir: s.dir)],
      line.mode == 'tab'
          ? [
              for (final c in line.cells)
                Cell(col: c.col, str: c.str, fret: c.fret)
            ]
          : const [],
    );
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Chords copied')));
  }

  /// Overlays the copied chord/strum/cell layers onto [line], clipped to its
  /// own length. Lyrics are never touched, so this works on a line that's
  /// already full of lyrics — the gap [_duplicateLine] leaves.
  void _pasteChords(Line line) {
    final clip = _chordClipboard;
    if (clip == null) return;
    _structural(() {
      line.chords
        ..clear()
        ..addAll(clip.chords.where((c) => c.col < line.length));
      line.strums
        ..clear()
        ..addAll(clip.strums.where((s) => s.col < line.length));
      if (clip.cells.isNotEmpty) {
        line.cells
          ..clear()
          ..addAll(clip.cells.where((c) => c.col < line.length));
      }
    });
  }

  /// Moves a line to a new position within its section.
  void _reorderLine(int si, int oldIndex, int newIndex) {
    _structural(() {
      final lines = song!.sections[si].lines;
      lines.insert(newIndex, lines.removeAt(oldIndex));
    });
  }

  /// Pastes several lines of lyrics at once; each newline becomes its own
  /// chords-mode line (no staff), lyric row populated, chord row empty —
  /// chords get tapped on afterward, word by word (see docs/ARCHITECTURE.md).
  Future<void> _addChordsParagraph(int si) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chords paragraph'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Paste or type a verse, one lyric line per row.\n'
                  'Tap chords onto it afterward.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || controller.text.isEmpty) return;
    _structural(() {
      for (final row in controller.text.split('\n')) {
        song!.sections[si].lines.add(_chordsLineFromLyricRow(row));
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
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title')),
              TextField(
                  controller: artist,
                  decoration: const InputDecoration(labelText: 'Artist')),
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
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Continue')),
            ],
          ),
        );
        if (!mounted || proceed != true) return;
      }
    }
    setState(() {
      s.title = title.text.trim().isEmpty ? s.title : title.text.trim();
      s.artist = artist.text.trim();
      s.tuning = tuning.text.trim().split(RegExp(r'\s+'));
      if (newBeats != oldBeats) {
        s.beatsPerMeasure = newBeats;
        // Re-lay every line onto the new measure grid (docs/ARCHITECTURE.md): each
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
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
              hintText:
                  'Capo, practice notes, tutorial links…\nURLs become tappable.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => song!.notes = controller.text.trim());
    _touch();
  }

  /// True once every line in the song is a bare placeholder — no cells,
  /// chords, or lyrics anywhere. Used so [_populateFromLyrics] can tell "an
  /// untouched fresh song" apart from "already has real content."
  bool _isBlank(Song s) => s.sections.every((sec) => sec.lines
      .every((l) => l.cells.isEmpty && l.chords.isEmpty && l.lyrics.isEmpty));

  /// Builds one chords-mode line per row of `text` — blank rows become an
  /// empty line — mirroring whatever line breaks the source (lyrics.ovh's
  /// paragraphs, or a paste) already has, exactly like [_addChordsParagraph].
  /// Appended to the end of the song's last section; a genuinely blank song
  /// has that placeholder replaced outright instead of left as a stray empty
  /// line in front, which amounts to "starts from the beginning."
  void _populateFromLyrics(String text) {
    final s = song!;
    final lines = [
      for (final row in text.split('\n')) _chordsLineFromLyricRow(row),
    ];
    _structural(() {
      if (_isBlank(s)) {
        s.sections
          ..clear()
          ..add(Section(name: '', lines: lines));
      } else {
        s.sections.last.lines.addAll(lines);
      }
    });
  }

  /// The paste side of [_startSongDialog]: a full ASCII tab (6-line blocks,
  /// `[Section]` headers, chord rows) parses into real sections via
  /// [parseTab]; anything else — plain lyrics, or a tab too mangled to
  /// recognize — falls back to [_populateFromLyrics] so the paste is never
  /// silently dropped.
  void _populateFromPaste(String text) {
    final imported = parseTab(text);
    if (imported.isEmpty) {
      _populateFromLyrics(text);
      return;
    }
    final s = song!;
    _structural(() {
      if (_isBlank(s)) {
        s.sections
          ..clear()
          ..addAll(imported);
      } else {
        s.sections.addAll(imported);
      }
    });
  }

  /// The "how do you want to start this song" entry point (SPEC-IMPORT
  /// §6.1): look up lyrics by artist/title, or paste them directly (lyrics
  /// or a full tab — see [_populateFromPaste]). Shown automatically once for
  /// a brand-new blank song, and reachable again later from the menu.
  Future<void> _startSongDialog() async {
    final artist = TextEditingController(text: song!.artist);
    final title = TextEditingController();
    final paste = TextEditingController();
    var pasting = false;
    var suggestions = <SongSuggestion>[];
    Timer? debounce;
    final result = await showDialog<_LyricsEntry>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        // lyrics.ovh's lookup needs an exact artist/title match and has no
        // fuzzy matching of its own (a typo just comes back "not found") —
        // this debounced search-as-you-type against its /suggest endpoint
        // (real Deezer search) is the actual help for misspellings; casing
        // alone doesn't matter to the lookup, so nothing special needed there.
        void search() {
          debounce?.cancel();
          final query = '${artist.text} ${title.text}'.trim();
          if (query.isEmpty) {
            setDialogState(() => suggestions = []);
            return;
          }
          debounce = Timer(const Duration(milliseconds: 350), () async {
            final found = await suggestSongs(query);
            if (ctx.mounted) setDialogState(() => suggestions = found);
          });
        }

        void pick(SongSuggestion s) {
          debounce?.cancel();
          Navigator.pop(ctx, _LyricsEntry.lookup(s.artist, s.title));
        }

        return AlertDialog(
          title: Text(pasting
              ? 'Paste the song'
              : 'Enter the artist and song to look up lyrics'),
          content: SizedBox(
            width: 480,
            child: pasting
                ? TextField(
                    controller: paste,
                    autofocus: true,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      hintText: 'Paste lyrics (or a full tab) here — chords '
                          'get tapped on afterward.',
                    ),
                  )
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                      controller: artist,
                      autofocus: true,
                      onChanged: (_) => search(),
                      decoration: const InputDecoration(labelText: 'Artist'),
                    ),
                    TextField(
                      controller: title,
                      onChanged: (_) => search(),
                      decoration:
                          const InputDecoration(labelText: 'Song title'),
                    ),
                    for (final s in suggestions)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.title),
                        subtitle: Text(s.artist),
                        onTap: () => pick(s),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
            TextButton(
              onPressed: () => setDialogState(() => pasting = !pasting),
              child: Text(pasting ? 'Look up instead' : 'Paste instead'),
            ),
            FilledButton(
              onPressed: () {
                if (pasting) {
                  if (paste.text.trim().isEmpty) return;
                  Navigator.pop(ctx, _LyricsEntry.paste(paste.text));
                } else {
                  if (artist.text.trim().isEmpty && title.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(
                      ctx,
                      _LyricsEntry.lookup(
                          artist.text.trim(), title.text.trim()));
                }
              },
              child: Text(pasting ? 'Add' : 'Look up'),
            ),
          ],
        );
      }),
    );
    debounce?.cancel();
    if (result == null || !mounted) return;
    if (result.pastedText != null) {
      _populateFromPaste(result.pastedText!);
      return;
    }
    final s = song!;
    setState(() => lookingUpLyrics = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Looking up lyrics…')));
    final lyrics = await fetchLyrics(result.artist!, result.title!);
    if (!mounted) return;
    setState(() => lookingUpLyrics = false);
    if (lyrics == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No lyrics found for this artist/title.')));
      return;
    }
    setState(() {
      if (result.artist!.isNotEmpty) s.artist = result.artist!;
      if (result.title!.isNotEmpty) s.title = result.title!;
    });
    _populateFromLyrics(lyrics);
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                        child: Text(s.title, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 16),
                  ]),
                ),
              )
            : Text(s.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Notation help',
            onPressed: () => showLegendDialog(context),
          ),
          if (s.mine)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: _undoStack.isEmpty ? null : _undo,
            ),
          if (s.mine)
            IconButton(
              icon: Icon(playView ? Icons.edit : Icons.play_arrow, size: 28),
              tooltip: playView ? 'Edit' : 'Play view',
              onPressed: () => setState(() {
                playView = !playView;
                _stopAutoScroll();
                cursor = null;
              }),
            ),
          if (s.mine)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'addLyrics' => _startSongDialog(),
                'settings' => _editSongSettings(),
                _ => _deleteSong(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'addLyrics',
                    child: Text('Look up lyrics / paste tab (new lines)')),
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
  Widget _card(Widget child, {Key? key}) => Card(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        color: Theme.of(context).colorScheme.surface,
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      );

  Widget _buildPlayView(Song s) {
    return Column(children: [
      Expanded(
        child: ListView(
          controller: _playScroll,
          padding: const EdgeInsets.all(16),
          children: [
            NotesCard(notes: s.notes),
            for (final section in s.sections) ...[
              if (section.name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(section.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              for (final line in section.lines)
                _card(TabStaff(line: line, tuning: s.tuning, scale: _playZoom)),
            ],
          ],
        ),
      ),
      _playControls(),
    ]);
  }

  /// Play view's autoscroll (play/pause + speed) and zoom, as +/- steppers
  /// rather than a Slider (unused elsewhere in this app, and steppers are
  /// trivial to drive from widget tests).
  Widget _playControls() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            icon: Icon(_autoScrolling ? Icons.pause : Icons.play_arrow),
            tooltip: _autoScrolling ? 'Pause autoscroll' : 'Autoscroll',
            onPressed: _toggleAutoScroll,
          ),
          _stepper(
            icon: Icons.speed,
            onMinus: _scrollSpeed > 10
                ? () => setState(() => _scrollSpeed -= 10)
                : null,
            onPlus: _scrollSpeed < 150
                ? () => setState(() => _scrollSpeed += 10)
                : null,
          ),
          _stepper(
            icon: Icons.zoom_in,
            onMinus:
                _playZoom > 0.8 ? () => setState(() => _playZoom -= 0.1) : null,
            onPlus:
                _playZoom < 2.0 ? () => setState(() => _playZoom += 0.1) : null,
          ),
        ]),
      ),
    );
  }

  Widget _stepper({
    required IconData icon,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: const Icon(Icons.remove, size: 18),
        onPressed: onMinus,
      ),
      Icon(icon,
          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      IconButton(
        icon: const Icon(Icons.add, size: 18),
        onPressed: onPlus,
      ),
    ]);
  }

  /// Zoom stepper for edit view, mirroring [_playControls]'s: shrinking
  /// column width fits more of a wide line on screen at once, so lining up
  /// a chord over the right word doesn't require scrolling back and forth.
  Widget _editZoomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _stepper(
          icon: Icons.zoom_in,
          onMinus:
              _editZoom > 0.6 ? () => setState(() => _editZoom -= 0.1) : null,
          onPlus:
              _editZoom < 1.5 ? () => setState(() => _editZoom += 0.1) : null,
        ),
      ]),
    );
  }

  Widget _buildEditor(Song s, bool narrow) {
    return Focus(
      focusNode: focus,
      onKeyEvent: _onKey,
      child: Column(children: [
        _editZoomBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              NotesCard(notes: s.notes, onEdit: _editNotes),
              for (var si = 0; si < s.sections.length; si++) ..._section(s, si),
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
            onClose: () => setState(() => cursor = null),
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
          child:
              Text(section.name, style: Theme.of(context).textTheme.titleSmall),
        ),
      if (section.lines.isNotEmpty)
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) =>
              _reorderLine(si, oldIndex, newIndex),
          children: [
            for (var li = 0; li < section.lines.length; li++)
              _lineCard(s, si, li),
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          WoodLegibleButton(
            onPressed: () => _addTabLine(si),
            icon: Icons.piano,
            label: 'Tab line',
          ),
          WoodLegibleButton(
            onPressed: () => _addChordsParagraph(si),
            icon: Icons.lyrics_outlined,
            label: 'Chords paragraph',
          ),
        ]),
      ),
    ];
  }

  /// One editable line, keyed by its own identity so [ReorderableListView]
  /// can track it across drags. Drag handle and menu sit in a thin header
  /// strip *above* the staff, not beside it — on a phone, competing for
  /// horizontal room with the staff left too little width to work in. The
  /// drag handle is the only part of the card that starts a reorder —
  /// everything else (staff taps, the menu) needs to keep working untouched.
  Widget _lineCard(Song s, int si, int li) {
    final section = s.sections[si];
    final line = section.lines[li];
    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.max, children: [
          ReorderableDragStartListener(
            index: li,
            child: Icon(Icons.drag_indicator,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            iconSize: 18,
            onSelected: (v) {
              final cols = measureCols(s.beatsPerMeasure);
              switch (v) {
                case 'toggleMode':
                  _structural(() {
                    line.mode = line.mode == 'tab' ? 'chords' : 'tab';
                  });
                case 'insertAbove':
                  _insertLineAbove(si, li);
                case 'duplicate':
                  _duplicateLine(si, li);
                case 'copyChords':
                  _copyChords(line);
                case 'pasteChords':
                  _pasteChords(line);
                case 'grow':
                  _structural(() => line.addMeasure(cols));
                case 'shrink':
                  if (line.length > cols) {
                    _structural(() => line.removeMeasure(cols));
                  }
                case 'delete':
                  _structural(() {
                    section.lines.removeAt(li);
                    if (section.lines.isEmpty && s.sections.length > 1) {
                      s.sections.removeAt(si);
                    }
                  });
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggleMode',
                child: Text(line.mode == 'tab'
                    ? 'Switch to chords mode'
                    : 'Switch to tab mode'),
              ),
              const PopupMenuItem(
                  value: 'insertAbove', child: Text('Insert line above')),
              const PopupMenuItem(
                  value: 'duplicate', child: Text('Duplicate line')),
              const PopupMenuItem(
                  value: 'copyChords', child: Text('Copy chords')),
              PopupMenuItem(
                value: 'pasteChords',
                enabled: _chordClipboard != null,
                child: const Text('Paste chords'),
              ),
              const PopupMenuItem(value: 'grow', child: Text('Add measure')),
              const PopupMenuItem(
                  value: 'shrink', child: Text('Remove measure')),
              const PopupMenuItem(value: 'delete', child: Text('Delete line')),
            ],
          ),
        ]),
        TabStaff(
          line: line,
          tuning: s.tuning,
          editable: true,
          scale: _editZoom,
          cursorCol: _at(si, li) ? cursor!.col : null,
          cursorStr: _at(si, li) ? cursor!.str : null,
          onTapCell: (col, str) {
            setState(() => cursor = _Cursor(si, li, col, str));
            focus.requestFocus();
          },
          onTapChord: (col) => _editChord(line, col),
          onTapLyric: (col) => _editLyric(line, col),
          onTapStrum: (col) => _cycleStrum(line, col),
        ),
      ]),
      key: ValueKey(line),
    );
  }

  bool _at(int si, int li) =>
      cursor != null && cursor!.section == si && cursor!.line == li;
}
