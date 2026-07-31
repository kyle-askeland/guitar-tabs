/// Data model per docs/ARCHITECTURE.md. Strings are indexed 0 = low E; the
/// renderer reverses for display. `fret` is a string so it can hold
/// technique notation (`x`, `5h7`, `<12>`, ...), never parsed as a number.
library;

const standardTuning = ['E', 'A', 'D', 'G', 'B', 'E'];

class Cell {
  final int col;
  final int str;
  final String fret;

  Cell({required this.col, required this.str, required this.fret});

  factory Cell.fromJson(Map<String, dynamic> j) =>
      Cell(col: j['col'], str: j['str'], fret: j['fret']);

  Map<String, dynamic> toJson() => {'col': col, 'str': str, 'fret': fret};
}

/// A chord name displayed above the staff at a column (`G`, `Am7`, `D/F#`).
class ChordMark {
  final int col;
  final String name;

  ChordMark({required this.col, required this.name});

  factory ChordMark.fromJson(Map<String, dynamic> j) =>
      ChordMark(col: j['col'], name: j['name']);

  Map<String, dynamic> toJson() => {'col': col, 'name': name};
}

/// A run of lyrics anchored to a column, so words sit under the notes they
/// are sung on rather than at the start of the line.
class LyricMark {
  final int col;
  final String text;

  LyricMark({required this.col, required this.text});

  factory LyricMark.fromJson(Map<String, dynamic> j) =>
      LyricMark(col: j['col'], text: j['text']);

  Map<String, dynamic> toJson() => {'col': col, 'text': text};
}

/// A strum direction ('D' down, 'U' up) at a column — the rhythm layer,
/// shown as an arrow row above the chords rather than attached to any one
/// string.
class StrumMark {
  final int col;
  final String dir;

  StrumMark({required this.col, required this.dir});

  factory StrumMark.fromJson(Map<String, dynamic> j) =>
      StrumMark(col: j['col'], dir: j['dir']);

  Map<String, dynamic> toJson() => {'col': col, 'dir': dir};
}

class Line {
  final List<Cell> cells;
  final List<int> barlines;
  final List<ChordMark> chords;
  final List<LyricMark> lyrics;
  final List<StrumMark> strums;
  int length;
  /// "tab" (full six-string staff) or "chords" (chord/lyric rows only, no
  /// staff). Lives on the line, not the song, so one song can mix a
  /// fingerpicked intro with plain chords-and-lyrics verses.
  String mode;

  Line({
    List<Cell>? cells,
    List<int>? barlines,
    List<ChordMark>? chords,
    List<LyricMark>? lyrics,
    List<StrumMark>? strums,
    this.length = 32,
    this.mode = 'tab',
  })  : cells = cells == null ? [] : List.of(cells),
        barlines = barlines == null ? [8, 16, 24] : List.of(barlines),
        chords = chords == null ? [] : List.of(chords),
        lyrics = lyrics == null ? [] : List.of(lyrics),
        strums = strums == null ? [] : List.of(strums);

  factory Line.fromJson(Map<String, dynamic> j) => Line(
        cells: [for (final c in j['cells'] ?? []) Cell.fromJson(c)],
        barlines: List<int>.from(j['barlines'] ?? []),
        chords: [for (final c in j['chords'] ?? []) ChordMark.fromJson(c)],
        lyrics: _lyricsFrom(j),
        strums: [for (final s in j['strums'] ?? []) StrumMark.fromJson(s)],
        length: j['length'] ?? 32,
        mode: j['mode'] ?? 'tab',
      );

  /// Songs saved before lyrics were positionable stored one string per line;
  /// it becomes a mark at column 0.
  static List<LyricMark> _lyricsFrom(Map<String, dynamic> j) {
    final marks = [for (final l in j['lyrics'] ?? []) LyricMark.fromJson(l)];
    final legacy = j['lyric'] as String?;
    if (marks.isEmpty && legacy != null && legacy.isNotEmpty) {
      marks.add(LyricMark(col: 0, text: legacy));
    }
    return marks;
  }

  Map<String, dynamic> toJson() => {
        'cells': [for (final c in cells) c.toJson()],
        'barlines': barlines,
        'chords': [for (final c in chords) c.toJson()],
        'lyrics': [for (final l in lyrics) l.toJson()],
        'strums': [for (final s in strums) s.toJson()],
        'length': length,
        'mode': mode,
      };

  /// Display width of each column: widest cell across the six strings, min 1.
  /// Multi-character cells (`12`, `5h7`) widen their column so the strings
  /// stay vertically aligned (see docs/ARCHITECTURE.md).
  List<int> get columnWidths {
    final widths = List.filled(length, 1);
    for (final c in cells) {
      if (c.col < length && c.fret.length > widths[c.col]) {
        widths[c.col] = c.fret.length;
      }
    }
    return widths;
  }

  String? chordAt(int col) {
    for (final c in chords) {
      if (c.col == col) return c.name;
    }
    return null;
  }

  /// Sets, replaces, or (with an empty name) clears the chord at a column.
  void setChord(int col, String name) {
    chords.removeWhere((c) => c.col == col);
    if (name.isNotEmpty) {
      chords
        ..add(ChordMark(col: col, name: name))
        ..sort((a, b) => a.col - b.col);
    }
  }

  String? lyricAt(int col) {
    for (final l in lyrics) {
      if (l.col == col) return l.text;
    }
    return null;
  }

  /// Sets, replaces, or (with empty text) clears the lyric at a column.
  void setLyric(int col, String text) {
    lyrics.removeWhere((l) => l.col == col);
    if (text.isNotEmpty) {
      lyrics
        ..add(LyricMark(col: col, text: text))
        ..sort((a, b) => a.col - b.col);
    }
  }

  String? strumAt(int col) {
    for (final s in strums) {
      if (s.col == col) return s.dir;
    }
    return null;
  }

  /// Sets, replaces, or (with an empty dir) clears the strum at a column.
  void setStrum(int col, String dir) {
    strums.removeWhere((s) => s.col == col);
    if (dir.isNotEmpty) {
      strums
        ..add(StrumMark(col: col, dir: dir))
        ..sort((a, b) => a.col - b.col);
    }
  }

  Cell? cellAt(int col, int str) {
    for (final c in cells) {
      if (c.col == col && c.str == str) return c;
    }
    return null;
  }

  /// Sets, replaces, or (with an empty fret) clears the cell at (col, str).
  void setCell(int col, int str, String fret) {
    cells.removeWhere((c) => c.col == col && c.str == str);
    if (fret.isNotEmpty) cells.add(Cell(col: col, str: str, fret: fret));
  }

  /// Appends one full measure ([cols] columns, closed off by a new barline)
  /// to the end of the line.
  void addMeasure(int cols) {
    barlines.add(length);
    length += cols;
  }

  /// Removes the line's last measure ([cols] columns), dropping any
  /// cell/chord/lyric/barline that falls inside it. No-ops (returns false)
  /// if the line is already down to one measure.
  bool removeMeasure(int cols) {
    if (length <= cols) return false;
    length -= cols;
    cells.removeWhere((c) => c.col >= length);
    barlines.removeWhere((b) => b >= length);
    chords.removeWhere((c) => c.col >= length);
    lyrics.removeWhere((l) => l.col >= length);
    strums.removeWhere((s) => s.col >= length);
    return true;
  }

  /// Inserts one blank column at [col] (0..length), shifting every
  /// cell/chord/lyric/strum/barline at or after it one column to the right.
  /// The "add a chord slot here" action for a chords-mode line's per-word
  /// grid (docs/ARCHITECTURE.md) — unlike [addMeasure], which always appends
  /// a whole measure at the end, this opens room at exactly one spot, so an
  /// extra mid-phrase chord change doesn't need a column reserved next to
  /// every word up front.
  void insertColumn(int col) {
    int shift(int c) => c >= col ? c + 1 : c;
    final newCells = [
      for (final c in cells) Cell(col: shift(c.col), str: c.str, fret: c.fret)
    ];
    cells
      ..clear()
      ..addAll(newCells);
    final newChords = [
      for (final c in chords) ChordMark(col: shift(c.col), name: c.name)
    ];
    chords
      ..clear()
      ..addAll(newChords);
    final newLyrics = [
      for (final l in lyrics) LyricMark(col: shift(l.col), text: l.text)
    ];
    lyrics
      ..clear()
      ..addAll(newLyrics);
    final newStrums = [
      for (final s in strums) StrumMark(col: shift(s.col), dir: s.dir)
    ];
    strums
      ..clear()
      ..addAll(newStrums);
    final newBarlines = [for (final b in barlines) shift(b)];
    barlines
      ..clear()
      ..addAll(newBarlines);
    length += 1;
  }

  /// Removes the blank column at [col] — the counterpart to [insertColumn].
  /// No-ops (returns false) if that column actually holds a cell, chord,
  /// lyric or strum (removing content, not just reclaiming empty space,
  /// isn't this action's job — clear it first) or if it's the line's last
  /// remaining column.
  bool removeColumn(int col) {
    if (length <= 1) return false;
    if (cells.any((c) => c.col == col) ||
        chordAt(col) != null ||
        lyricAt(col) != null ||
        strumAt(col) != null) {
      return false;
    }
    int shift(int c) => c > col ? c - 1 : c;
    final newCells = [
      for (final c in cells) Cell(col: shift(c.col), str: c.str, fret: c.fret)
    ];
    cells
      ..clear()
      ..addAll(newCells);
    final newChords = [
      for (final c in chords) ChordMark(col: shift(c.col), name: c.name)
    ];
    chords
      ..clear()
      ..addAll(newChords);
    final newLyrics = [
      for (final l in lyrics) LyricMark(col: shift(l.col), text: l.text)
    ];
    lyrics
      ..clear()
      ..addAll(newLyrics);
    final newStrums = [
      for (final s in strums) StrumMark(col: shift(s.col), dir: s.dir)
    ];
    strums
      ..clear()
      ..addAll(newStrums);
    final newBarlines = [
      for (final b in barlines)
        if (b != col) shift(b)
    ];
    barlines
      ..clear()
      ..addAll(newBarlines);
    length -= 1;
    return true;
  }

  /// How many cells/chords/lyrics would be discarded by [remeasure] moving
  /// from [oldBeats] to [newBeats] beats per measure — content only fails to
  /// carry over when the measure grid *shrinks* and a mark lands past the
  /// new, narrower measure boundary. Barlines aren't counted: losing one is
  /// invisible plumbing, not content worth confirming.
  int remeasureLosses(int oldBeats, int newBeats) {
    final oldCols = measureCols(oldBeats), newCols = measureCols(newBeats);
    if (oldCols == newCols) return 0;
    bool lost(int col) => remapColumn(col, oldCols, newCols) == null;
    return cells.where((c) => lost(c.col)).length +
        chords.where((c) => lost(c.col)).length +
        lyrics.where((l) => lost(l.col)).length +
        strums.where((s) => lost(s.col)).length;
  }

  /// Re-lays the line onto a grid of [newBeats] beats per measure: every
  /// column (cells, chords, lyrics, barlines) keeps its
  /// (measure index, offset within measure) pair, just translated onto
  /// wider or narrower measures. An offset that no longer fits in its
  /// measure — only possible when shrinking — is dropped; see
  /// [remeasureLosses] to warn about that before calling this.
  void remeasure(int oldBeats, int newBeats) {
    final oldCols = measureCols(oldBeats), newCols = measureCols(newBeats);
    if (oldCols == newCols) return;
    final measures = (length + oldCols - 1) ~/ oldCols;
    length = (measures < 1 ? 1 : measures) * newCols;
    final newCells = [
      for (final c in cells)
        if (remapColumn(c.col, oldCols, newCols) case final nc?)
          Cell(col: nc, str: c.str, fret: c.fret)
    ];
    cells
      ..clear()
      ..addAll(newCells);
    final newChords = [
      for (final c in chords)
        if (remapColumn(c.col, oldCols, newCols) case final nc?)
          ChordMark(col: nc, name: c.name)
    ];
    chords
      ..clear()
      ..addAll(newChords);
    final newLyrics = [
      for (final l in lyrics)
        if (remapColumn(l.col, oldCols, newCols) case final nc?)
          LyricMark(col: nc, text: l.text)
    ];
    lyrics
      ..clear()
      ..addAll(newLyrics);
    final newStrums = [
      for (final s in strums)
        if (remapColumn(s.col, oldCols, newCols) case final nc?)
          StrumMark(col: nc, dir: s.dir)
    ];
    strums
      ..clear()
      ..addAll(newStrums);
    final newBarlines = [
      for (final b in barlines)
        if (remapColumn(b, oldCols, newCols) case final nb?) nb
    ];
    barlines
      ..clear()
      ..addAll(newBarlines);
  }
}

class Section {
  String name;
  final List<Line> lines;

  Section({required this.name, List<Line>? lines}) : lines = lines ?? [Line()];

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        name: j['name'] ?? '',
        lines: [for (final l in j['lines'] ?? []) Line.fromJson(l)],
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'lines': [for (final l in lines) l.toJson()]};
}

class Song {
  final String songId;
  String title;
  String artist;
  List<String> tuning; // low → high
  int beatsPerMeasure;
  String notes; // free text: practice notes, tutorial links, ...
  final String createdAt;
  String updatedAt;
  final List<Section> sections;
  final bool mine;

  Song({
    required this.songId,
    required this.title,
    this.artist = '',
    List<String>? tuning,
    this.beatsPerMeasure = 4,
    this.notes = '',
    this.createdAt = '',
    this.updatedAt = '',
    List<Section>? sections,
    this.mine = true,
  })  : tuning = tuning ?? List.of(standardTuning),
        sections = sections ?? [];

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        songId: j['songId'],
        title: j['title'] ?? '',
        artist: j['artist'] ?? '',
        tuning: List<String>.from(j['tuning'] ?? standardTuning),
        beatsPerMeasure: j['beatsPerMeasure'] ?? 4,
        notes: j['notes'] ?? '',
        createdAt: j['createdAt'] ?? '',
        updatedAt: j['updatedAt'] ?? '',
        sections: [for (final s in j['sections'] ?? []) Section.fromJson(s)],
        mine: j['mine'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'title': title,
        'artist': artist,
        'tuning': tuning,
        'beatsPerMeasure': beatsPerMeasure,
        'notes': notes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'sections': [for (final s in sections) s.toJson()],
      };
}

/// Column width of one measure: 2 columns per beat.
int measureCols(int beatsPerMeasure) => beatsPerMeasure * 2;

/// Maps a column from one measure grid to another, keeping its
/// (measure index, offset within measure) pair. Returns null if the offset
/// no longer fits under the new grid — e.g. beat 4 of a 4/4 measure has
/// nowhere to go in 3/4.
int? remapColumn(int col, int oldCols, int newCols) {
  final offset = col % oldCols;
  return offset < newCols ? (col ~/ oldCols) * newCols + offset : null;
}

/// Barlines every [beatsPerMeasure] * 2 columns (2 columns per beat), up to
/// but excluding [length]. With the default beatsPerMeasure of 4 and a
/// 4-measure line ([length] 32) this reproduces the default `[8, 16, 24]`
/// spacing exactly.
List<int> defaultBarlines(int length, int beatsPerMeasure) {
  final cols = measureCols(beatsPerMeasure);
  return [for (var b = cols; b < length; b += cols) b];
}

/// Default length (in columns) of a freshly added line. One measure by
/// default, since even that alone can run past a phone's width once fret
/// numbers widen columns; "Add measure" grows it from there.
int defaultLineLength(int beatsPerMeasure, {int measures = 1}) =>
    measureCols(beatsPerMeasure) * measures;

/// List-view projection: what `GET /songs` returns (no tab data).
class SongSummary {
  final String songId;
  final String title;
  final String artist;
  final String updatedAt;
  final bool mine;

  SongSummary({
    required this.songId,
    required this.title,
    this.artist = '',
    this.updatedAt = '',
    this.mine = true,
  });

  factory SongSummary.fromJson(Map<String, dynamic> j) => SongSummary(
        songId: j['songId'],
        title: j['title'] ?? '',
        artist: j['artist'] ?? '',
        updatedAt: j['updatedAt'] ?? '',
        mine: j['mine'] ?? true,
      );
}
