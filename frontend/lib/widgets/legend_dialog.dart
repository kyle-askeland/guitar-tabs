import 'package:flutter/material.dart';

import 'tab_staff.dart';

/// One notation symbol: what it's typed as, an example cell, and what it means.
class _Symbol {
  final String key, example, meaning;
  const _Symbol(this.key, this.example, this.meaning);
}

const _symbols = [
  _Symbol('h', '5h7', 'hammer-on'),
  _Symbol('p', '7p5', 'pull-off'),
  _Symbol('b', '7b9', 'bend'),
  _Symbol('r', '7b9r7', 'bend release'),
  _Symbol('/', '5/7', 'slide up'),
  _Symbol('\\', '7\\5', 'slide down'),
  _Symbol('x', 'x', 'muted / dead note'),
  _Symbol('~', '7~', 'vibrato'),
  _Symbol('t', '12t', 'tapping'),
  _Symbol('( )', '(5)', 'ghost / optional note'),
  _Symbol('< >', '<12>', 'natural harmonic'),
];

/// Explains the technique symbols and how chained cells like `5h7` are typed,
/// so the notation doesn't need to be reverse-engineered from the staff.
/// Reachable from every editor screen (owners and read-only visitors alike)
/// via the `?` icon in the app bar.
Future<void> showLegendDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Notation'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'A cell chains a fret and a technique the same way you\'d type '
                'it: fret, then technique letter, then another fret. Typing '
                '5, then h, then 7 produces one cell, 5h7 — a hammer-on from '
                'fret 5 to fret 7. On the phone fretboard pad, tap a fret, '
                'then a technique symbol, then the next fret, the same way.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final sym in _symbols)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 56,
                      child: Text(sym.key,
                          style: tabTextStyle.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(sym.example, style: tabTextStyle),
                    ),
                    Expanded(child: Text(sym.meaning)),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  SizedBox(
                    width: 56,
                    child: Text('PM', style: tabTextStyle.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 70),
                  const Expanded(child: Text('palm mute (marked above the staff)')),
                ]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}
