import 'package:flutter/material.dart';

/// Touch input for the editor (SPECS §5): fret numbers 0–24 plus the
/// technique symbols, so phones never need the OS keyboard. Numbers arrive
/// as whole tokens ("12"), symbols as single characters.
class FretPad extends StatelessWidget {
  final void Function(String) onInput;
  final VoidCallback onClear;

  const FretPad({super.key, required this.onInput, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var fret = 0; fret <= 24; fret++)
                    _key('$fret', () => onInput('$fret')),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final sym in ['x', 'h', 'p', 'b', 'r', '/', r'\', '~', 't', '|'])
                    _key(sym, () => onInput(sym)),
                  _key('⌫', onClear),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(40, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(label),
        ),
      );
}
