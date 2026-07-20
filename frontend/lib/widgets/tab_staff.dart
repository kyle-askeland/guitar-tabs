import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/song.dart';

/// Monospace style for ASCII contexts (the import dialog).
const tabTextStyle = TextStyle(fontFamily: 'monospace', fontSize: 15, height: 1.3);

/// One tab line drawn as a real staff: six solid string lines, fret numbers
/// in chips that knock out the line behind them, barlines spanning the six
/// strings, a chord row above and a lyric row below — both anchored to
/// columns, so a chord and the words sung under it line up with their notes.
///
/// Painted as a single CustomPaint with tap hit-testing — far cheaper than
/// 6×N GestureDetectors, and every column is a full-height tap target.
class TabStaff extends StatelessWidget {
  final Line line;
  final List<String> tuning;
  final int? cursorCol, cursorStr;
  final bool editable;
  final double scale;
  final void Function(int col, int str)? onTapCell;
  final void Function(int col)? onTapChord;
  final void Function(int col)? onTapLyric;
  final void Function(int col)? onTapStrum;

  const TabStaff({
    super.key,
    required this.line,
    required this.tuning,
    this.cursorCol,
    this.cursorStr,
    this.editable = false,
    this.scale = 1,
    this.onTapCell,
    this.onTapChord,
    this.onTapLyric,
    this.onTapStrum,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = _Metrics(line, scale, editable);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: GestureDetector(
        onTapDown: editable ? (d) => _tap(m, d.localPosition) : null,
        child: CustomPaint(
          size: Size(m.width, m.height),
          painter: _StaffPainter(
            line: line,
            tuning: tuning,
            m: m,
            cursorCol: cursorCol,
            cursorStr: cursorStr,
            editable: editable,
            ink: theme.colorScheme.onSurface,
            muted: theme.colorScheme.onSurfaceVariant,
            accent: theme.colorScheme.primary,
            bg: theme.colorScheme.surface,
          ),
        ),
      ),
    );
  }

  void _tap(_Metrics m, Offset pos) {
    final col = m.colAt(pos.dx);
    if (pos.dy < m.strumH) {
      onTapStrum?.call(col);
    } else if (pos.dy < m.strumH + m.chordH) {
      onTapChord?.call(col);
    } else if (pos.dy < m.strumH + m.chordH + m.staffH) {
      final row = ((pos.dy - m.strumH - m.chordH) / m.rowH).floor().clamp(0, 5);
      onTapCell?.call(col, 5 - row); // top row = high e = str 5
    } else {
      onTapLyric?.call(col);
    }
  }
}

class _Metrics {
  final Line line;
  final double scale;
  late final double rowH = 26 * scale;
  late final double labelW = 26 * scale;
  late final double strumH;
  late final double chordH;
  late final double lyricH;
  /// Height of the six-string staff area — zero in `chords` mode, where
  /// there's no staff at all, just chord names over lyrics.
  late final double staffH;
  late final List<double> colW;
  late final List<double> colX; // absolute start x of each column
  late final double width;
  late final double height;

  _Metrics(this.line, this.scale, bool editable) {
    staffH = line.mode == 'chords' ? 0 : 6 * rowH;
    strumH = (editable || line.strums.isNotEmpty) ? 20 * scale : 0;
    chordH = (editable || line.chords.isNotEmpty) ? 22 * scale : 0;
    lyricH = (editable || line.lyrics.isNotEmpty) ? 24 * scale : 0;
    final charW = _measure('0', _cellStyle(scale, null)).width;
    colW = [
      for (final w in line.columnWidths)
        math.max(30 * scale, w * charW + 12 * scale)
    ];
    colX = List.filled(line.length, 0);
    var x = labelW;
    for (var c = 0; c < line.length; c++) {
      colX[c] = x;
      x += colW[c];
    }
    // Chords and lyrics anchored near the end would otherwise run off the
    // canvas; widen it to whatever the longest one needs.
    var text = x;
    for (final ch in line.chords) {
      if (ch.col < line.length) {
        final cx = colX[ch.col] + colW[ch.col] / 2;
        text = math.max(text, cx + _measure(ch.name, _chordStyle(scale, null)).width / 2);
      }
    }
    for (final ly in line.lyrics) {
      if (ly.col < line.length) {
        text = math.max(text, colX[ly.col] + _measure(ly.text, _lyricStyle(scale, null)).width);
      }
    }
    width = math.max(x, text + 6 * scale) + 2;
    height = strumH + chordH + staffH + lyricH;
  }

  /// x of the staff's right edge — where the closing barline is drawn. Not
  /// [width], which may be padded out by a long chord or lyric.
  double get staffEnd => colX.isEmpty ? labelW : colX.last + colW.last;

  int colAt(double x) {
    for (var c = 0; c < line.length; c++) {
      if (x < colX[c] + colW[c]) return c;
    }
    return line.length - 1;
  }
}

TextStyle _cellStyle(double scale, Color? color) => TextStyle(
      fontFamily: 'monospace',
      fontSize: 14 * scale,
      fontWeight: FontWeight.w600,
      color: color,
    );

TextStyle _chordStyle(double scale, Color? color) => TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5 * scale,
      fontWeight: FontWeight.w700,
      color: color,
    );

/// Lyrics are content, not annotation: plain roman, so they stay legible at
/// 13px on a phone. (The placeholder hints stay italic — see [_hintStyle].)
TextStyle _lyricStyle(double scale, Color? color) => TextStyle(
      fontSize: 13 * scale,
      fontWeight: FontWeight.w500,
      color: color,
    );

TextPainter _measure(String text, TextStyle style, [TextSpan? span]) =>
    TextPainter(
      text: span ?? TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

class _StaffPainter extends CustomPainter {
  final Line line;
  final List<String> tuning;
  final _Metrics m;
  final int? cursorCol, cursorStr;
  final bool editable;
  final Color ink, muted, accent, bg;

  _StaffPainter({
    required this.line,
    required this.tuning,
    required this.m,
    required this.cursorCol,
    required this.cursorStr,
    required this.editable,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.bg,
  });

  double _sy(int row) => m.strumH + m.chordH + row * m.rowH + m.rowH / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final hasStaff = m.staffH > 0;
    _paintCursor(canvas);
    if (hasStaff) {
      _paintStrings(canvas);
      _paintBars(canvas);
      _paintCells(canvas);
    }
    _paintStrums(canvas);
    _paintChords(canvas);
    _paintLyrics(canvas);
    if (hasStaff) _paintHint(canvas);
    _paintCursorOutline(canvas);
  }

  void _paintCursor(Canvas canvas) {
    final col = cursorCol;
    if (col == null || col >= line.length || m.staffH == 0) return;
    canvas.drawRect(
      Rect.fromLTWH(m.colX[col], m.strumH + m.chordH, m.colW[col], m.staffH),
      Paint()..color = accent.withValues(alpha: .12),
    );
    final str = cursorStr;
    if (str != null) {
      canvas.drawRect(
        Rect.fromLTWH(
            m.colX[col], _sy(5 - str) - m.rowH / 2, m.colW[col], m.rowH),
        Paint()..color = accent.withValues(alpha: .22),
      );
    }
  }

  /// A crisp outline around the selected cell, so where input lands is
  /// unmistakable (painted last, above chips).
  void _paintCursorOutline(Canvas canvas) {
    final col = cursorCol, str = cursorStr;
    if (col == null || str == null || col >= line.length || m.staffH == 0) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(m.colX[col] + 1, _sy(5 - str) - m.rowH / 2 + 1,
            m.colW[col] - 2, m.rowH - 2),
        const Radius.circular(4),
      ),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * m.scale,
    );
  }

  /// On an untouched line, say how to start; disappears at the first tap.
  void _paintHint(Canvas canvas) {
    if (!editable || line.cells.isNotEmpty || cursorCol != null) return;
    final tp = _measure(
      'tap a string, then enter a fret',
      TextStyle(
          fontStyle: FontStyle.italic, fontSize: 12 * m.scale, color: muted),
    );
    final pos = Offset(m.labelW + 12 * m.scale, m.chordH + 3 * m.rowH - tp.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(pos.dx - 4, pos.dy, tp.width + 8, tp.height),
      Paint()..color = bg,
    );
    tp.paint(canvas, pos);
  }

  void _paintStrings(Canvas canvas) {
    final paint = Paint()
      ..color = ink.withValues(alpha: .8)
      ..strokeWidth = 1.4 * m.scale;
    final labelStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12 * m.scale,
      color: muted,
    );
    for (var row = 0; row < 6; row++) {
      final y = _sy(row);
      canvas.drawLine(Offset(m.labelW, y), Offset(m.staffEnd, y), paint);
      final str = 5 - row;
      final label = str == 5 ? tuning[str].toLowerCase() : tuning[str];
      final tp = _measure(label, labelStyle);
      tp.paint(canvas, Offset(m.labelW - tp.width - 6 * m.scale, y - tp.height / 2));
    }
  }

  void _paintBars(Canvas canvas) {
    final paint = Paint()
      ..color = ink.withValues(alpha: .8)
      ..strokeWidth = 1.5 * m.scale;
    void bar(double x) =>
        canvas.drawLine(Offset(x, _sy(0)), Offset(x, _sy(5)), paint);
    bar(m.labelW + 0.75);
    bar(m.staffEnd - 0.75);
    for (final b in line.barlines) {
      if (b > 0 && b < line.length) bar(m.colX[b]);
    }
  }

  void _paintCells(Canvas canvas) {
    final base = _cellStyle(m.scale, ink);
    final symStyle = TextStyle(color: accent, fontWeight: FontWeight.w700);
    for (final cell in line.cells) {
      if (cell.col >= line.length) continue;
      final span = TextSpan(style: base, children: [
        for (final ch in cell.fret.split(''))
          TextSpan(text: ch, style: '0123456789'.contains(ch) ? null : symStyle),
      ]);
      final tp = _measure('', base, span);
      final cx = m.colX[cell.col] + m.colW[cell.col] / 2;
      final cy = _sy(5 - cell.str);
      // Knock the string line out behind the number, like engraved tab.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: tp.width + 6 * m.scale,
              height: tp.height),
          const Radius.circular(3),
        ),
        Paint()..color = bg,
      );
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      // Slur arc over hammer-ons and pull-offs (5h7, 7p5); a straight
      // diagonal over slides (5/7, 7\5) — curved = slur, straight = slide,
      // the same distinction as printed tab. The diagonal's slope mirrors
      // the typed symbol itself (`/` slopes up, `\` slopes down), so the
      // direction reads without parsing the fret numbers.
      final slideDir = RegExp(r'^\d+([/\\])\d+$').firstMatch(cell.fret)?.group(1);
      if (RegExp(r'^\d+[hp]\d+$').hasMatch(cell.fret)) {
        canvas.drawArc(
          Rect.fromLTWH(cx - tp.width / 2, cy - tp.height / 2 - 6 * m.scale,
              tp.width, 8 * m.scale),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4 * m.scale,
        );
      } else if (slideDir != null) {
        final rect = Rect.fromLTWH(cx - tp.width / 2,
            cy - tp.height / 2 - 6 * m.scale, tp.width, 8 * m.scale);
        final up = slideDir == '/';
        canvas.drawLine(
          up ? rect.bottomLeft : rect.topLeft,
          up ? rect.topRight : rect.bottomRight,
          Paint()
            ..color = accent
            ..strokeWidth = 1.6 * m.scale
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  /// Full-width pill behind the chord/lyric strips in edit mode — makes it
  /// obvious the whole strip is tappable, anywhere along the line.
  void _bubble(Canvas canvas, Rect r) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    canvas.drawRRect(rr, Paint()..color = muted.withValues(alpha: .08));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = muted.withValues(alpha: .3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  TextStyle get _hintStyle => TextStyle(
        fontStyle: FontStyle.italic,
        fontSize: 11 * m.scale,
        color: muted.withValues(alpha: .6),
      );

  /// Arrow row above the chords: ↓ for a downstrum, ↑ for an upstrum. Downs
  /// are painted full-strength and ups dimmed, echoing how strumming-pattern
  /// charts bold the downbeats — direction reads from the glyph, weight from
  /// the color, so it still lands at a glance in grayscale.
  void _paintStrums(Canvas canvas) {
    if (m.strumH == 0) return;
    final row = Rect.fromLTWH(m.labelW, 1, m.width - m.labelW - 2, m.strumH - 2);
    if (editable) _bubble(canvas, row);
    if (line.strums.isEmpty) {
      if (!editable) return;
      final tp = _measure('tap above any column for a down/up strum', _hintStyle);
      tp.paint(canvas,
          Offset(m.labelW + 10 * m.scale, row.center.dy - tp.height / 2));
      return;
    }
    for (final s in line.strums) {
      if (s.col >= line.length) continue;
      final down = s.dir == 'D';
      final style = TextStyle(
        fontSize: 14 * m.scale,
        fontWeight: FontWeight.w900,
        color: down ? accent : accent.withValues(alpha: .55),
      );
      final tp = _measure(down ? '↓' : '↑', style);
      tp.paint(canvas,
          Offset(m.colX[s.col] + m.colW[s.col] / 2 - tp.width / 2, row.center.dy - tp.height / 2));
    }
  }

  void _paintChords(Canvas canvas) {
    if (m.chordH == 0) return;
    final row = Rect.fromLTWH(m.labelW, m.strumH + 1, m.width - m.labelW - 2, m.chordH - 4);
    if (editable) _bubble(canvas, row);
    if (line.chords.isEmpty) {
      if (!editable) return;
      final tp = _measure('tap above any column to add a chord', _hintStyle);
      tp.paint(canvas,
          Offset(m.labelW + 10 * m.scale, row.center.dy - tp.height / 2));
      return;
    }
    final style = _chordStyle(m.scale, accent);
    for (final ch in line.chords) {
      if (ch.col >= line.length) continue;
      final tp = _measure(ch.name, style);
      final cx = m.colX[ch.col] + m.colW[ch.col] / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, row.center.dy - tp.height / 2));
    }
  }

  void _paintLyrics(Canvas canvas) {
    if (m.lyricH == 0) return;
    final top = m.strumH + m.chordH + m.staffH;
    final row =
        Rect.fromLTWH(m.labelW, top + 3, m.width - m.labelW - 2, m.lyricH - 6);
    if (editable) _bubble(canvas, row);
    if (line.lyrics.isEmpty) {
      if (!editable) return;
      final tp = _measure('tap under any column to add lyrics', _hintStyle);
      tp.paint(canvas,
          Offset(m.labelW + 10 * m.scale, row.center.dy - tp.height / 2));
      return;
    }
    final style = _lyricStyle(m.scale, muted);
    for (final ly in line.lyrics) {
      if (ly.col >= line.length) continue;
      final tp = _measure(ly.text, style);
      tp.paint(canvas, Offset(m.colX[ly.col] + 1, row.center.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _StaffPainter old) => true;
}
