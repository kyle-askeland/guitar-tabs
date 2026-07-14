/// Parses pasted ASCII tab (the format used across the internet) into the
/// data model. Recognizes, per SPECS §3 notation:
/// - blocks of 6 consecutive tab lines (`e|---3---|`) → one [Line]
/// - `[Intro]` / `Verse:` style headers → section boundaries
/// - a chord-name row right above a block (`  G     Am7`) → [ChordMark]s
/// - a plain-text row right after a block → [LyricMark]s, anchored to the
///   column each run of words sits over
library;

import 'song.dart';

const _tokenChars = '0123456789hpbrtxX/\\~()<>';

/// Sections parsed from pasted text; empty if no tab block was found.
List<Section> parseTab(String text) {
  final src = text.split('\n');
  final sections = <Section>[];
  String? pendingChords; // raw line, kept for character positions

  void addLine(Line line) {
    if (sections.isEmpty) sections.add(Section(name: '', lines: []));
    sections.last.lines.add(line);
  }

  var i = 0;
  while (i < src.length) {
    final trimmed = src[i].trim();
    if (trimmed.isEmpty) {
      pendingChords = null;
      i++;
      continue;
    }
    if (_isTabLine(src[i]) &&
        i + 5 < src.length &&
        [for (var k = 1; k < 6; k++) src[i + k]].every(_isTabLine)) {
      final block = src.sublist(i, i + 6);
      i += 6;
      // A plain text line immediately after the block holds its lyrics.
      String? lyricRow;
      if (i < src.length) {
        final after = src[i].trim();
        if (after.isNotEmpty &&
            !_isTabLine(src[i]) &&
            _sectionName(after) == null &&
            !_isChordRow(after)) {
          lyricRow = src[i];
          i++;
        }
      }
      addLine(_parseBlock(block, pendingChords, lyricRow));
      pendingChords = null;
      continue;
    }
    final name = _sectionName(trimmed);
    if (name != null) {
      sections.add(Section(name: name, lines: []));
      pendingChords = null;
    } else if (_isChordRow(trimmed)) {
      pendingChords = src[i];
    } else {
      pendingChords = null;
    }
    i++;
  }
  return [
    for (final s in sections)
      if (s.lines.isNotEmpty) s
  ];
}

String _stripClosingPipe(String body) =>
    body.endsWith('|') ? body.substring(0, body.length - 1) : body;

/// A tab line: an optional short string label, a `|`, then only tab
/// characters (dashes, frets, techniques, bars).
bool _isTabLine(String raw) {
  final l = raw.trim();
  final pipe = l.indexOf('|');
  if (pipe < 0 || pipe > 3) return false;
  final body = l.substring(pipe + 1);
  if (body.isEmpty || !body.contains('-')) return false;
  return !body.contains(RegExp(r'[^-0-9hpbrtxX/\\~()<>|. ]'));
}

final _chordToken =
    RegExp(r'^[A-G][#b]?(m|maj|min|dim|aug|M)?\d*(sus\d?|add\d+)?(/[A-G][#b]?)?$');

bool _isChordRow(String trimmed) {
  final tokens = trimmed.split(RegExp(r'\s+'));
  return tokens.isNotEmpty && tokens.every(_chordToken.hasMatch);
}

String? _sectionName(String trimmed) {
  final bracketed = RegExp(r'^\[(.+)\]:?$').firstMatch(trimmed);
  if (bracketed != null) return bracketed.group(1)!.trim();
  final word = RegExp(
    r'^(intro|verse|chorus|bridge|solo|outro|pre-?chorus|interlude|riff)\b\s*\d*\s*:?$',
    caseSensitive: false,
  );
  if (word.hasMatch(trimmed)) {
    return trimmed.replaceAll(':', '').trim();
  }
  return null;
}

/// rows[0] = high e (str 5) … rows[5] = low E (str 0), standard tab order.
Line _parseBlock(List<String> rows, String? chordRow, String? lyricRow) {
  final labelLen = rows[0].indexOf('|') + 1;
  // The trailing pipe is the line's closing edge (the renderer always draws
  // one), not a column — strip it before mapping positions.
  final bodies = [
    for (final r in rows)
      _stripClosingPipe(r.trimRight().substring(r.trimRight().indexOf('|') + 1))
  ];
  var maxLen = 0;
  for (final b in bodies) {
    if (b.length > maxLen) maxLen = b.length;
  }

  // Bar characters occupy a column in ASCII but are metadata in the model:
  // map char positions to logical columns, skipping bars.
  final barChars = <int>{};
  for (final b in bodies) {
    for (var p = 0; p < b.length; p++) {
      if (b[p] == '|') barChars.add(p);
    }
  }
  final colOf = List<int>.filled(maxLen, 0);
  var col = 0;
  for (var p = 0; p < maxLen; p++) {
    colOf[p] = col;
    if (!barChars.contains(p)) col++;
  }

  final line = Line(
    barlines: {for (final p in barChars) colOf[p]}.toList()..sort(),
    length: col > 0 ? col : 1,
  );

  for (var row = 0; row < 6; row++) {
    final str = 5 - row;
    final b = bodies[row];
    var p = 0;
    while (p < b.length) {
      if (_tokenChars.contains(b[p])) {
        var q = p + 1;
        while (q < b.length && _tokenChars.contains(b[q])) {
          q++;
        }
        line.setCell(colOf[p], str, b.substring(p, q));
        p = q;
      } else {
        p++;
      }
    }
  }

  /// Character position in an annotation row → the column it sits over.
  int columnAt(int start) {
    final p = start - labelLen;
    return p < 0 ? 0 : (p < maxLen ? colOf[p] : line.length - 1);
  }

  if (chordRow != null) {
    for (final m in RegExp(r'\S+').allMatches(chordRow)) {
      final col = columnAt(m.start);
      if (line.chordAt(col) == null) line.setChord(col, m.group(0)!);
    }
  }

  if (lyricRow != null) {
    // Single spaces hold a phrase together; two or more start a new run,
    // which is how spaced-out syllables get anchored to their own columns.
    for (final m in RegExp(r'\S+(?: \S+)*').allMatches(lyricRow)) {
      final col = columnAt(m.start);
      if (line.lyricAt(col) == null) line.setLyric(col, m.group(0)!);
    }
  }
  return line;
}
