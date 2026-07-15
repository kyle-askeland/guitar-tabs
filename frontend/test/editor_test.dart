import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/screens/editor_screen.dart';
import 'package:guitar_tabs/storage/song_store.dart';
import 'package:guitar_tabs/widgets/tab_staff.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'a brand-new song opens in edit view; the toggle switches to play view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');

    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle();

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

    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle(); // a new song opens straight into edit view

    FilledButton saveButton() => tester.widget<FilledButton>(
        find.byType(FilledButton));
    expect(saveButton().onPressed, isNull); // clean → blocked
    expect(find.text('Saved'), findsOneWidget);

    // A fresh line defaults to chords mode; switch it to tab to reach the
    // fret staff (SPEC-DISPLAY-MODES §4).
    await tester.tap(find.text('Chords'));
    await tester.pump();

    // Tap col 0 / high e on the staff, then type a fret.
    await tester.tapAt(_staff(tester) + const Offset(41, 35));
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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle(); // a new song opens straight into edit view

    await tester.tapAt(_staff(tester) + const Offset(41, 10)); // chord row, col 0
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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle(); // a new song opens straight into edit view

    // A fresh line defaults to chords mode; switch it to tab so the lyric
    // row sits below a full six-string staff (SPEC-DISPLAY-MODES §4).
    await tester.tap(find.text('Chords'));
    await tester.pump();

    // lyric row (below the six strings), column 3
    await tester.tapAt(_staff(tester) + const Offset(41 + 30 * 3, 22 + 6 * 26 + 12));
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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle();

    expect(find.text('Chords'), findsOneWidget);
    expect(find.text('Tab'), findsNothing);
  });

  testWidgets('+ Tab line adds a blank tab-mode line alongside the default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Test song');
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle();

    // Default line is chords mode; switch to tab and stamp a fret.
    await tester.tap(find.text('Chords'));
    await tester.pump();
    await tester.tapAt(_staff(tester) + const Offset(41, 35));
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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle(); // a new song opens straight into edit view

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
    await tester.pumpWidget(MaterialApp(home: EditorScreen(id: song.songId)));
    await tester.pumpAndSettle(); // a new song opens straight into edit view

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
}

/// Top-left of the staff canvas; geometry at scale 1 is labelW 26, chordH 22,
/// rowH 26, min column width 30.
Offset _staff(WidgetTester tester) => tester.getTopLeft(find
    .descendant(of: find.byType(TabStaff), matching: find.byType(CustomPaint))
    .first);
