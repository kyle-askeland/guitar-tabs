import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Touch input for the editor: a tappable fretboard instead of number keys.
/// Tap where your fingers go — the fret number lands on that string in the
/// active column, so a chord is a few taps in one column. Dots mirror the
/// active column's notes (two-way), the position row slides the window up
/// the neck, and a symbol row covers techniques (see docs/ARCHITECTURE.md).
///
/// The window shows [_window] frets: four is what fits a phone without the
/// last one being squeezed off the edge.
class FretboardPad extends StatefulWidget {
  /// The active column's fret text per string (index 0 = low E … 5 = high e).
  final List<String> column;
  final List<String> tuning;
  final void Function(int str, int fret) onFret;
  final void Function(String symbol) onSymbol;
  final VoidCallback onClear, onPrev, onNext, onClose;

  const FretboardPad({
    super.key,
    required this.column,
    required this.tuning,
    required this.onFret,
    required this.onSymbol,
    required this.onClear,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  @override
  State<FretboardPad> createState() => _FretboardPadState();
}

const _headerH = 16.0, _rowH = 24.0, _labelW = 24.0, _openW = 32.0;
const _window = 4; // frets visible at once
const _positions = [1, 3, 5, 7, 9, 12];

class _FretboardPadState extends State<FretboardPad> {
  int start = 1; // first fret of the visible window

  List<int> get _frets =>
      [for (final f in widget.column) int.tryParse(f) ?? -1];

  @override
  void didUpdateWidget(FretboardPad old) {
    super.didUpdateWidget(old);
    // Keep the selected column's notes visible: slide the window if needed.
    final fretted = _frets.where((f) => f > 0);
    if (fretted.isNotEmpty) {
      final lo = fretted.reduce(math.min);
      final hi = fretted.reduce(math.max);
      if (lo < start || hi > start + _window - 1) start = lo.clamp(1, 20);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      // Swipe down anywhere on the pad to dismiss it, mirroring the close
      // button — a phone user's thumb is already down here, not up at a
      // corner "X".
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 200) widget.onClose();
      },
      child: Material(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final p in _positions)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: OutlinedButton(
                              onPressed: () => setState(() => start = p),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                backgroundColor:
                                    start == p ? scheme.primaryContainer : null,
                              ),
                              child: Text('$p–${p + _window - 1}'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_hide_outlined),
                  tooltip: 'Close fretboard',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                ),
              ]),
              const SizedBox(height: 4),
              LayoutBuilder(builder: (context, constraints) {
                final size = Size(constraints.maxWidth, _headerH + 6 * _rowH);
                return GestureDetector(
                  onTapDown: (d) => _tap(d.localPosition, size.width),
                  child: CustomPaint(
                    key: const Key('fretboard'),
                    size: size,
                    painter: _BoardPainter(
                      frets: _frets,
                      tuning: widget.tuning,
                      start: start,
                      ink: scheme.onSurface,
                      muted: scheme.onSurfaceVariant,
                      accent: scheme.primary,
                      onAccent: scheme.onPrimary,
                      faint: scheme.surfaceContainerHighest,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              Row(children: [
                _key(context, '←', widget.onPrev),
                _key(context, '→', widget.onNext),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final sym in [
                          'h',
                          'p',
                          'b',
                          'r',
                          '/',
                          r'\',
                          '~',
                          'x',
                          '|'
                        ])
                          _key(context, sym, () => widget.onSymbol(sym)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _key(context, '⌫', widget.onClear),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(BuildContext context, String label, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(38, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(label),
        ),
      );

  void _tap(Offset pos, double width) {
    if (pos.dy < _headerH || pos.dx < _labelW) return;
    final row = ((pos.dy - _headerH) / _rowH).floor().clamp(0, 5);
    final str = 5 - row; // top row = high e
    if (pos.dx < _labelW + _openW) {
      widget.onFret(str, 0);
    } else {
      final fretW = (width - _labelW - _openW) / _window;
      final i =
          ((pos.dx - _labelW - _openW) / fretW).floor().clamp(0, _window - 1);
      widget.onFret(str, start + i);
    }
  }
}

const _inlays = {3, 5, 7, 9, 15, 17, 19, 21};

class _BoardPainter extends CustomPainter {
  final List<int> frets; // per string, -1 = none
  final List<String> tuning;
  final int start;
  final Color ink, muted, accent, onAccent, faint;

  _BoardPainter({
    required this.frets,
    required this.tuning,
    required this.start,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.faint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fretW = (size.width - _labelW - _openW) / _window;
    const boardL = _labelW + _openW;
    const top = _headerH + _rowH / 2;
    const bottom = _headerH + 5 * _rowH + _rowH / 2;
    double sy(int row) => _headerH + row * _rowH + _rowH / 2;
    double fx(int i) =>
        boardL + i * fretW + fretW / 2; // center of window fret i

    final numStyle =
        TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: muted);
    void text(String s, TextStyle st, Offset center) {
      final tp = TextPainter(
          text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    // fret numbers
    text('0', numStyle, const Offset(_labelW + _openW / 2, _headerH / 2));
    for (var i = 0; i < _window; i++) {
      text('${start + i}', numStyle, Offset(fx(i), _headerH / 2));
    }

    // inlay dots
    final inlayPaint = Paint()..color = faint;
    for (var i = 0; i < _window; i++) {
      final fret = start + i;
      const mid = (top + bottom) / 2;
      if (fret == 12) {
        canvas.drawCircle(Offset(fx(i), mid - _rowH), 4, inlayPaint);
        canvas.drawCircle(Offset(fx(i), mid + _rowH), 4, inlayPaint);
      } else if (_inlays.contains(fret)) {
        canvas.drawCircle(Offset(fx(i), mid), 4, inlayPaint);
      }
    }

    // nut (thick when the window starts at fret 1) and fret wires
    final nutPaint = Paint()
      ..color = ink.withValues(alpha: .8)
      ..strokeWidth = start == 1 ? 3.5 : 1.5;
    canvas.drawLine(
        const Offset(boardL, top), const Offset(boardL, bottom), nutPaint);
    final wirePaint = Paint()
      ..color = muted.withValues(alpha: .45)
      ..strokeWidth = 1.2;
    for (var i = 1; i <= _window; i++) {
      final x = boardL + i * fretW;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), wirePaint);
    }

    // strings (thicker toward low E) and labels
    final labelStyle =
        TextStyle(fontFamily: 'monospace', fontSize: 11, color: muted);
    for (var row = 0; row < 6; row++) {
      final str = 5 - row;
      canvas.drawLine(
        Offset(_labelW, sy(row)),
        Offset(size.width, sy(row)),
        Paint()
          ..color = ink.withValues(alpha: .8)
          ..strokeWidth = 2.4 - str * 0.28,
      );
      text(str == 5 ? tuning[str].toLowerCase() : tuning[str], labelStyle,
          Offset(_labelW / 2, sy(row)));
    }

    // finger dots for the active column
    final dotStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: onAccent);
    for (var str = 0; str < 6; str++) {
      final f = frets[str];
      if (f < 0) continue;
      final y = sy(5 - str);
      if (f == 0) {
        canvas.drawCircle(
          Offset(_labelW + _openW / 2, y),
          7,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else if (f >= start && f <= start + _window - 1) {
        final c = Offset(fx(f - start), y);
        canvas.drawCircle(c, 9.5, Paint()..color = accent);
        text('$f', dotStyle, c);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
