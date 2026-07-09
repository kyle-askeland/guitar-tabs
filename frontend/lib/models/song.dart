/// Data model per SPECS §3. Strings are indexed 0 = low E; the renderer
/// reverses for display. `fret` is a string so it can hold technique
/// notation (`x`, `5h7`, `<12>`, ...), never parsed as a number.
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

class Line {
  final List<Cell> cells;
  final List<int> barlines;
  int length;

  Line({List<Cell>? cells, List<int>? barlines, this.length = 40})
      : cells = cells ?? [],
        barlines = barlines ?? [8, 16, 24, 32];

  factory Line.fromJson(Map<String, dynamic> j) => Line(
        cells: [for (final c in j['cells'] ?? []) Cell.fromJson(c)],
        barlines: List<int>.from(j['barlines'] ?? []),
        length: j['length'] ?? 40,
      );

  Map<String, dynamic> toJson() => {
        'cells': [for (final c in cells) c.toJson()],
        'barlines': barlines,
        'length': length,
      };

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
  int capo;
  final String createdAt;
  String updatedAt;
  final List<Section> sections;
  final bool mine;

  Song({
    required this.songId,
    required this.title,
    this.artist = '',
    List<String>? tuning,
    this.capo = 0,
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
        capo: j['capo'] ?? 0,
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
        'capo': capo,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'sections': [for (final s in sections) s.toJson()],
      };
}

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
