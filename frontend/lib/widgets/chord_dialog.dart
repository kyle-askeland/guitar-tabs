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
/// The shape is the movable voicing from [chordFrets]; the base fret is the
/// one thing the app can't guess, so it's a stepper that starts at the
/// lowest position for the chosen root.
Future<ChordChoice?> showChordDialog(
  BuildContext context, {
  String? existing,
}) {
  final parsed = existing == null ? null : splitChord(existing);
  var root = parsed?.$1 ?? 'E';
  var quality = parsed?.$2 ?? '';
  var base = defaultBaseFor(root, quality);

  return showDialog<ChordChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final frets = resolveFrets(root, quality, base);
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
                      base = defaultBaseFor(r, quality);
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
                      base = defaultBaseFor(root, q);
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
                      ? () => setState(
                          () => base = base == null ? baseFretFor(root) : base! + 1)
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
