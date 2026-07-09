/// ASCII tab rendering per SPECS §3 — the single implementation of the
/// notation rules. Grid display, play view, and text export all use this.
library;

import 'song.dart';

/// Display width of each column: widest cell across all strings, min 1.
/// Multi-character cells (`12`, `5h7`) widen the column; the other strings
/// get extra dashes so everything stays vertically aligned.
List<int> columnWidths(Line line) {
  final widths = List.filled(line.length, 1);
  for (final c in line.cells) {
    if (c.col < line.length && c.fret.length > widths[c.col]) {
      widths[c.col] = c.fret.length;
    }
  }
  return widths;
}

/// Renders one line as 6 rows of text, high e on top. `tuning` is low → high;
/// the top row's label is lowercased (`e B G D A E`), matching convention.
List<String> renderLine(Line line, List<String> tuning) {
  final widths = columnWidths(line);
  return [
    for (var str = 5; str >= 0; str--)
      _renderString(line, str, str == 5 ? tuning[str].toLowerCase() : tuning[str], widths),
  ];
}

String _renderString(Line line, int str, String label, List<int> widths) {
  final buf = StringBuffer('$label|');
  for (var col = 0; col < line.length; col++) {
    if (col > 0 && line.barlines.contains(col)) buf.write('|');
    final fret = line.cellAt(col, str)?.fret ?? '';
    buf.write(fret.padRight(widths[col], '-'));
  }
  buf.write('|');
  return buf.toString();
}

/// Full song as plain ASCII text (the "Export as text" output).
String renderSong(Song song) {
  final buf = StringBuffer('${song.title}\n');
  if (song.artist.isNotEmpty) buf.write('${song.artist}\n');
  if (song.capo > 0) buf.write('Capo ${song.capo}\n');
  for (final section in song.sections) {
    buf.write('\n[${section.name}]\n');
    for (final line in section.lines) {
      buf.writeAll(renderLine(line, song.tuning), '\n');
      buf.write('\n\n');
    }
  }
  return buf.toString();
}
