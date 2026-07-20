/// Pure parsing logic for the vaclavblazej/tabs bulk import (ARCHITECTURE.md,
/// Import tooling) — no network I/O, so it's unit-testable on its own.
/// `bin/` wires this up to GitHub/the app API.
library;

import 'package:guitar_tabs/models/song.dart';
import 'package:guitar_tabs/models/tab_import.dart';

/// `"Alt-J - Breezeblocks.tab"` → title "Breezeblocks", artist "Alt-J".
/// Files with no ` - ` separator (e.g. `other/Bella Ciao`, no extension)
/// become a title with an empty artist.
(String, String) titleArtistFromFilename(String name) {
  final base = name.endsWith('.tab') ? name.substring(0, name.length - 4) : name;
  final idx = base.indexOf(' - ');
  if (idx < 0) return (base.trim(), '');
  return (base.substring(idx + 3).trim(), base.substring(0, idx).trim());
}

class Header {
  final List<String> tuning;
  final String notes;
  final String body;
  Header(this.tuning, this.notes, this.body);
}

final _headerLineRe = RegExp(r'^[A-Za-z][A-Za-z0-9 /]*:\s');
final _dropDRe = RegExp(r'drop\s*d\b', caseSensitive: false);

/// The metadata block (`source:`, `video:`/`audio:`, `capo:`, `note:`) —
/// possibly several blank-line-separated mini-paragraphs of it (e.g.
/// `source:`/`video:`/`note:` as one paragraph, then a bare `drop D` line as
/// its own paragraph before the real body starts). A line only counts as
/// header/metadata if it's blank, matches `key: value`, or is the bare
/// tuning hint — anything else (a `[Section]` header, a chord row, plain
/// lyrics) ends the header, however early that happens. Some files have no
/// metadata header at all (a handful of `other/`/`melodies/` files are just
/// an unbroken lead sheet) — for those the loop stops on line one and the
/// whole text is the body, not silently swallowed as "header".
Header parseHeader(String raw) {
  final lines = raw.split('\n');
  var i = 0;
  final headerLines = <String>[];
  while (i < lines.length) {
    final t = lines[i].trim();
    if (t.isEmpty || _headerLineRe.hasMatch(t) || _dropDRe.hasMatch(t)) {
      headerLines.add(lines[i]);
      i++;
    } else {
      break;
    }
  }
  final body = lines.sublist(i).join('\n');

  final tuning = List.of(standardTuning);
  final notes = <String>[];
  for (final line in headerLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // Only drop D shows up as free text in these files, not a `tuning:`
    // header field — a substring check is all there is to key off of.
    if (_dropDRe.hasMatch(line)) {
      tuning[0] = 'D'; // low string down a whole step; rest stay standard
    }
    // `capo: N` lines (like every other header field) just carry straight
    // into notes — capo has no dedicated Song field, it's free text there.
    notes.add(trimmed);
  }
  return Header(tuning, notes.join('\n'), body);
}

String dedupKey(String title, String artist) =>
    '${title.trim().toLowerCase()}::${artist.trim().toLowerCase()}';

// ---- body → sections ----

/// Splits the body on `[Section]` header lines — most sample files use
/// them, but plenty don't (a handful of `other/` and `melodies/` files are
/// just an unbroken lead sheet, no headers anywhere). Trailing text on a
/// header line itself (inline chords, or junk like a repeat marker) is kept
/// as the section's first body line so `parseTab` still sees it. Falls back
/// to one unnamed section covering the whole body when no header matched —
/// the same "unnamed until a header shows up" default `parseTab` itself
/// uses — so a header-less file still gets parsed instead of dropped.
List<MapEntry<String, String>> splitSections(String body) {
  final headerRe = RegExp(r'^\s*\[([^\]]+)\](.*)$');
  final blocks = <MapEntry<String, String>>[];
  String? name;
  var buf = <String>[];
  void flush() {
    if (name != null) blocks.add(MapEntry(name!, buf.join('\n')));
  }

  for (final raw in body.split('\n')) {
    final m = headerRe.firstMatch(raw);
    if (m != null) {
      flush();
      name = m.group(1)!.trim();
      buf = [m.group(2) ?? ''];
    } else {
      buf.add(raw);
    }
  }
  flush();
  return blocks.isEmpty ? [MapEntry('', body)] : blocks;
}

/// Real files sometimes trail a per-line annotation in brackets (`[8x]`,
/// `[rit.]`) after real content — most often on one row of a tab block,
/// which otherwise breaks that row's tab-line recognition outright. Only
/// strips when something other than the bracket precedes it on the line, so
/// a genuine `[Section]` header (the whole line, nothing before the
/// bracket) is left untouched for `splitSections`/`parseTab` to recognize.
String stripTrailingAnnotations(String text) => text.split('\n').map((line) {
      final m = RegExp(r'^(.*?)(\s*\[[^\[\]]*\]\s*)$').firstMatch(line);
      return (m != null && m.group(1)!.trim().isNotEmpty) ? m.group(1)! : line;
    }).join('\n');

/// A handful of files in this repo are just a pointer to another file (a
/// "cover" stub referencing the original, e.g. `Smash Mouth - I'm A Believer
/// (cover).tab` whose entire content is the literal line `The Monkees - I'm
/// A Believer.tab`) — recognizably a single line ending in `.tab`, no real
/// content. Worth special-casing so it comes out as "genuinely nothing to
/// import" rather than a song whose only lyric is a filename.
bool _isRedirectStub(String body) {
  final trimmed = body.trim();
  return !trimmed.contains('\n') && trimmed.toLowerCase().endsWith('.tab');
}

List<Section> buildSections(String rawBody) {
  if (_isRedirectStub(rawBody)) return [];
  final body = stripTrailingAnnotations(rawBody);
  final sections = <Section>[];
  for (final block in splitSections(body)) {
    final name = block.key;
    final text = block.value;
    // Try the app's own parser first, but only trust it when it actually
    // found real fret data (a `[Fingerstyle]`-style block): parseTab's
    // chord-row regex is strict, so on messier real-world text it can
    // partially match (one clean chord row) while silently discarding the
    // rest of the same section — exactly what the permissive fallback
    // below is for. When there's no real tab to lose, always prefer the
    // permissive parser: it handles clean chord names just as well and
    // additionally covers non-standard shorthand without ever dropping a
    // line.
    final tabResult = parseTab(name.isEmpty ? text : '[$name]\n$text');
    final hasRealTab =
        tabResult.isNotEmpty && tabResult.single.lines.any((l) => l.cells.isNotEmpty);
    final lines = hasRealTab ? tabResult.single.lines : parseChordsPermissive(text);
    if (lines.isNotEmpty) sections.add(Section(name: name, lines: lines));
  }
  return sections;
}

/// Fallback for section bodies `parseTab`'s stricter chord-row regex can't
/// make sense of — real-world files use non-standard shorthand (`Dm.`,
/// `D5'D5'D5'D5'`, `F'` for a held/repeated hit) that no manual-paste chord
/// name should be guessed at, but that's still worth keeping for a
/// secondhand reference import. Walks line by line so nothing is dropped: a
/// chord-ish line pairs with the next as chords+lyrics (anchored by raw
/// character index, same idea as tab_import.dart's chords-only lines);
/// anything else becomes its own lyric-only line.
List<Line> parseChordsPermissive(String body) {
  final rawLines = body.split('\n');
  final out = <Line>[];
  var i = 0;
  while (i < rawLines.length) {
    final trimmed = rawLines[i].trim();
    if (trimmed.isEmpty) {
      i++;
      continue;
    }
    if (looksChordish(trimmed)) {
      final chordLine = rawLines[i];
      String? lyricRow;
      if (i + 1 < rawLines.length) {
        final next = rawLines[i + 1].trim();
        if (next.isNotEmpty && !looksChordish(next)) {
          lyricRow = rawLines[i + 1];
          i++; // consume the lyric row too
        }
      }
      out.add(chordsOnlyLine(chordLine, lyricRow));
      i++;
      continue;
    }
    out.add(Line(
      mode: 'chords',
      barlines: const [],
      length: trimmed.isEmpty ? 1 : trimmed.length,
      lyrics: [LyricMark(col: 0, text: trimmed)],
    ));
    i++;
  }
  return out;
}

final _chordish = RegExp(r"^[A-G][#b]?[A-Za-z0-9.'^]*$");

/// Permissive stand-in for tab_import.dart's `_isChordRow`: every token
/// must at least start like a chord root, but tolerates the non-standard
/// trailing shorthand (`Dm.`, `D5'D5'D5'D5'`) real files use.
bool looksChordish(String trimmed) {
  final tokens = trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  return tokens.isNotEmpty && tokens.every(_chordish.hasMatch);
}

/// Same anchoring idea as tab_import.dart's private `_parseChordsOnly`
/// (raw character index = column) — small enough to duplicate here rather
/// than expose purely for this messier, script-only heuristic.
Line chordsOnlyLine(String chordRow, String? lyricRow) {
  var maxLen = chordRow.length;
  if (lyricRow != null && lyricRow.length > maxLen) maxLen = lyricRow.length;
  final line = Line(barlines: const [], length: maxLen > 0 ? maxLen : 1, mode: 'chords');
  for (final m in RegExp(r'\S+').allMatches(chordRow)) {
    if (line.chordAt(m.start) == null) line.setChord(m.start, m.group(0)!);
  }
  if (lyricRow != null) {
    for (final m in RegExp(r'\S+(?: \S+)*').allMatches(lyricRow)) {
      if (line.lyricAt(m.start) == null) line.setLyric(m.start, m.group(0)!);
    }
  }
  return line;
}
