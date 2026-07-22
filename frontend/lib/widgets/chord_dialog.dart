import 'package:flutter/material.dart';

import '../models/chords.dart';

/// What the chord dialog hands back. [name] empty means "remove the chord";
/// [frets] non-null means "also stamp these notes into the column".
class ChordChoice {
  final String name;
  final List<int?>? frets;

  const ChordChoice(this.name, [this.frets]);
}

/// Pick a chord for a column, and optionally fill the tab underneath it.
/// When there's no open shape, the shape is whichever movable barre family
/// (E-shape or A-shape, see [defaultMovableShape]) reaches the root at the
/// lower fret; the base fret is the one thing the app can't guess beyond
/// that, so it's a stepper that starts at that lowest position.
Future<ChordChoice?> showChordDialog(
  BuildContext context, {
  String? existing,
  /// Chords-mode lines only (docs/ARCHITECTURE.md's per-word chord grid):
  /// room for an extra chord next to this word. Null hides the button.
  VoidCallback? onInsertSlot,
  /// Only offered when this column is itself an unused slot — reclaims the
  /// space. Null hides the button.
  VoidCallback? onRemoveSlot,
}) {
  final parsed = existing == null ? null : splitChord(existing);
  var root = parsed?.$1 ?? 'E';
  var quality = parsed?.$2 ?? '';
  var (family, base) = defaultShapeFor(root, quality);

  return showDialog<ChordChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final frets = resolveFrets(root, quality, family, base);
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('Chord'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final r in chordRoots)
                  ChoiceChip(
                    label: Text(r),
                    selected: r == root,
                    // A new root defaults to its open-position shape when one
                    // exists, otherwise the lowest barre position; the
                    // stepper below still lets you slide it up the neck.
                    onSelected: (_) => setState(() {
                      root = r;
                      (family, base) = defaultShapeFor(r, quality);
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final q in chordQualities)
                  ChoiceChip(
                    label: Text(q.isEmpty ? 'major' : q),
                    selected: q == quality,
                    onSelected: (_) => setState(() {
                      quality = q;
                      (family, base) = defaultShapeFor(root, q);
                    }),
                  ),
              ]),
              const Divider(height: 28),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: base != null && base! > 0
                      ? () => setState(() => base = base! - 1)
                      : null,
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    base == null ? 'Open position' : 'Base fret $base',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: base == null || base! < 15
                      ? () => setState(() {
                          if (base == null) {
                            (family, base) = defaultMovableShape(root, quality)!;
                          } else {
                            base = base! + 1;
                          }
                        })
                      : null,
                ),
              ]),
              const SizedBox(height: 10),
              Text('$root$quality — low E to high e',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                [for (final f in frets) f?.toString() ?? 'x'].join('  '),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
          ),
        ),
        actionsOverflowButtonSpacing: 4,
        actions: [
          if (onRemoveSlot != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRemoveSlot();
              },
              child: const Text('Remove slot'),
            ),
          if (onInsertSlot != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onInsertSlot();
              },
              child: const Text('Add slot after'),
            ),
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, const ChordChoice('')),
              child: const Text('Remove'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ChordChoice('$root$quality')),
            child: const Text('Name only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ChordChoice('$root$quality', frets)),
            child: const Text('Fill tab'),
          ),
        ],
      );
    }),
  );
}
