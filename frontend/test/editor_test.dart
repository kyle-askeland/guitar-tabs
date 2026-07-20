import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/song.dart';
import 'package:guitar_tabs/screens/editor_screen.dart';
import 'package:guitar_tabs/storage/song_store.dart';
import 'package:guitar_tabs/widgets/tab_staff.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps a fresh EditorScreen for `song` and dismisses the "look up / paste
/// lyrics" start dialog a brand-new blank song shows automatically, so
/// existing tests can interact with the editor underneath undisturbed.
Future<void> _pumpNewSong(WidgetTester tester, Song song) async {
  await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a brand-new song opens in edit view; the toggle switches to play view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');

    await _pumpNewSong(tester, song);

    // Edit view already: Save bar is showing, and the toggle offers play view.
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Saved'), findsNothing);
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('save button is disabled until an edit, saves on press',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');

    await _pumpNewSong(tester, song);

    FilledButton saveButton() => tester.widget<FilledButton>(
        find.byType(FilledButton));
    expect(saveButton().onPressed, isNull); // clean → blocked
    expect(find.text('Saved'), findsOneWidget);

    // A fresh line defaults to chords mode; switch it to tab to reach the
    // fret staff (see docs/ARCHITECTURE.md).
    await tester.tap(find.text('Chords'));
    await tester.pump();

    // Tap col 0 / high e on the staff, then type a fret.
    await tester.tapAt(_staff(tester) + const Offset(41, 55));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();

    expect(saveButton().onPressed, isNotNull); // dirty → enabled

    // Nothing hit the store yet: the stored song still has no cells.
    var stored = await store.fetch(song.songId);
    expect(stored.sections, isEmpty);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(saveButton().onPressed, isNull); // saved → blocked again
    stored = await store.fetch(song.songId);
    expect(stored.sections.single.lines.single.cellAt(0, 5)!.fret, '3');
  });

  testWidgets('picking a chord stamps its shape into the column below',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    await tester.tapAt(_staff(tester) + const Offset(41, 30)); // chord row, col 0
    await tester.pumpAndSettle();
    expect(find.text('Open position'), findsOneWidget); // default root E

    await tester.tap(find.text('G')); // root G has an open shape too
    await tester.pumpAndSettle();
    expect(find.text('Open position'), findsOneWidget);
    expect(find.text('3  2  0  0  0  3'), findsOneWidget);

    await tester.tap(find.text('Fill tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final line = (await store.fetch(song.songId)).sections.single.lines.single;
    expect(line.chordAt(0), 'G');
    expect([for (var s = 0; s < 6; s++) line.cellAt(0, s)!.fret],
        ['3', '2', '0', '0', '0', '3']);
  });

  testWidgets('lyrics anchor to the column they were tapped under',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // A fresh line defaults to chords mode; switch it to tab so the lyric
    // row sits below a full six-string staff (see docs/ARCHITECTURE.md).
    await tester.tap(find.text('Chords'));
    await tester.pump();

    // lyric row (below the six strings), column 3
    await tester.tapAt(_staff(tester) + const Offset(41 + 30 * 3, 20 + 22 + 6 * 26 + 12));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello darkness');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final line = (await store.fetch(song.songId)).sections.single.lines.single;
    expect(line.lyricAt(3), 'hello darkness');
  });

  testWidgets('a brand-new song\'s first line defaults to chords mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    expect(find.text('Chords'), findsOneWidget);
    expect(find.text('Tab'), findsNothing);
  });

  testWidgets('+ Tab line adds a blank tab-mode line alongside the default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    await tester.tap(find.text('Tab line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final lines = (await store.fetch(song.songId)).sections.single.lines;
    expect(lines.map((l) => l.mode), ['chords', 'tab']);
  });

  testWidgets(
      '+ Chords paragraph splits pasted lyrics into one chords-mode line per row',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    await tester.tap(find.text('Chords paragraph'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'line one\nline two\nline three');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // The default line the song opened with, plus the three pasted rows.
    final lines = (await store.fetch(song.songId)).sections.single.lines;
    expect(lines.length, 4);
    expect(lines.skip(1).every((l) => l.mode == 'chords'), isTrue);
    expect(lines[1].lyricAt(0), 'line one');
    expect(lines[2].lyricAt(0), 'line two');
    expect(lines[3].lyricAt(0), 'line three');
  });

  testWidgets('the mode chip flips a line between tab and chords, losslessly',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // Default line is chords mode; switch to tab and stamp a fret.
    await tester.tap(find.text('Chords'));
    await tester.pump();
    await tester.tapAt(_staff(tester) + const Offset(41, 55));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();

    // Flip back to chords and back to tab: the fret survives (§2, lossless).
    await tester.tap(find.text('Tab'));
    await tester.pump();
    await tester.tap(find.text('Chords'));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final line = (await store.fetch(song.songId)).sections.single.lines.single;
    expect(line.mode, 'tab');
    expect(line.cellAt(0, 5)!.fret, '3');
  });

  testWidgets('an invalid tuning blocks Save with an inline error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // Scoped to the AppBar: each line also has its own more_vert menu.
    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song settings'));
    await tester.pumpAndSettle();

    final tuningField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Tuning (low to high)');
    TextButton dialogSave() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));

    await tester.enterText(tuningField, 'Z A D G B E'); // Z isn't a note
    await tester.pump();
    expect(
        find.text('Each note must be A-G, optionally # or b (e.g. E A D G B E)'),
        findsOneWidget);
    expect(dialogSave().onPressed, isNull);

    await tester.enterText(tuningField, 'D A D G B'); // only 5 notes
    await tester.pump();
    expect(find.text('Enter exactly 6 notes, space separated'), findsOneWidget);
    expect(dialogSave().onPressed, isNull);

    await tester.enterText(tuningField, 'D A D G B E'); // valid: drop D tuning
    await tester.pump();
    expect(dialogSave().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final stored = await store.fetch(song.songId);
    expect(stored.tuning, ['D', 'A', 'D', 'G', 'B', 'E']);
  });

  testWidgets('an invalid beats-per-measure blocks Save with an inline error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // Scoped to the AppBar: each line also has its own more_vert menu.
    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song settings'));
    await tester.pumpAndSettle();

    final beatsField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Beats per measure');
    TextButton dialogSave() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));

    await tester.enterText(beatsField, '0');
    await tester.pump();
    expect(find.text('Enter a whole number from 1 to 32'), findsOneWidget);
    expect(dialogSave().onPressed, isNull);

    await tester.enterText(beatsField, '3');
    await tester.pump();
    expect(dialogSave().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final stored = await store.fetch(song.songId);
    expect(stored.beatsPerMeasure, 3);
  });

  testWidgets('undo reverts the last cell edit, undo button reflects state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    IconButton undoButton() =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo));
    expect(undoButton().onPressed, isNull); // nothing to undo on a fresh song

    await tester.tap(find.text('Chords'));
    await tester.pump();
    await tester.tapAt(_staff(tester) + const Offset(41, 55));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(undoButton().onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final stored = await store.fetch(song.songId);
    expect(stored.sections.single.lines.single.cellAt(0, 5), isNull);
  });

  testWidgets('Ctrl/Cmd+Z triggers undo from the keyboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    await tester.tap(find.text('Chords'));
    await tester.pump();
    await tester.tapAt(_staff(tester) + const Offset(41, 55));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final stored = await store.fetch(song.songId);
    expect(stored.sections.single.lines.single.cellAt(0, 5), isNull);
  });

  testWidgets('the ? icon opens a notation legend explaining symbol chaining',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text('hammer-on'), findsOneWidget);
    expect(find.text('pull-off'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('hammer-on'), findsNothing);
  });

  testWidgets('play view autoscroll toggles cleanly without leaking a timer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // Enough lines that play view actually has something to scroll —
    // otherwise autoscroll reaches maxScrollExtent (0) on its first tick
    // and immediately stops itself. The list is a lazy sliver even with a
    // plain `children:` list, so the button scrolls out of the built range
    // as lines pile up — scrollUntilVisible keeps it reachable.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 8; i++) {
      await tester.scrollUntilVisible(find.text('Tab line'), 300,
          scrollable: scrollable);
      await tester.tap(find.text('Tab line'));
      await tester.pump();
    }

    await tester.tap(find.byIcon(Icons.play_arrow)); // Play/Edit toggle
    await tester.pumpAndSettle();

    // Autoscroll's play/pause button — the only remaining play_arrow icon
    // once the app bar toggle has switched to Icons.edit.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('Duplicate line inserts a copy directly below the original',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // Give the default line a fret so the copy is easy to tell apart from a
    // freshly-added blank line.
    await tester.tap(find.text('Chords'));
    await tester.pump();
    await tester.tapAt(_staff(tester) + const Offset(41, 55));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final lines = (await store.fetch(song.songId)).sections.single.lines;
    expect(lines.length, 2);
    expect(lines[0].cellAt(0, 5)!.fret, '3');
    expect(lines[1].cellAt(0, 5)!.fret, '3');
  });

  testWidgets('dragging a line by its handle reorders it within the section',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await _pumpNewSong(tester, song);

    // The default blank line plus two chords-mode lines, "AAA" then "BBB".
    await tester.tap(find.text('Chords paragraph'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AAA\nBBB');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Drag the "AAA" line's handle down past "BBB".
    await tester.drag(
        find.byIcon(Icons.drag_indicator).at(1), const Offset(0, 200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final lines = (await store.fetch(song.songId)).sections.single.lines;
    expect(lines.map((l) => l.lyricAt(0)), [null, 'BBB', 'AAA']);
  });
}

/// Top-left of the staff canvas; geometry at scale 1 is labelW 26, strumH 20,
/// chordH 22, rowH 26, min column width 30.
Offset _staff(WidgetTester tester) => tester.getTopLeft(find
    .descendant(of: find.byType(TabStaff), matching: find.byType(CustomPaint))
    .first);
