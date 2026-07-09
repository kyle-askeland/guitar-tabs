import 'package:flutter/material.dart';

import '../models/song.dart';
import '../models/tab_text.dart';

const tabTextStyle = TextStyle(fontFamily: 'monospace', fontSize: 15, height: 1.3);

/// One editable tab line: 6 rows (high e on top) of tappable cells, rendered
/// character-for-character like the ASCII export (dashes, pipes, padding).
class TabGrid extends StatelessWidget {
  final Line line;
  final List<String> tuning;
  final int? cursorCol;
  final int? cursorStr;
  final void Function(int col, int str) onTapCell;

  const TabGrid({
    super.key,
    required this.line,
    required this.tuning,
    required this.onTapCell,
    this.cursorCol,
    this.cursorStr,
  });

  @override
  Widget build(BuildContext context) {
    final widths = columnWidths(line);
    final highlight = Theme.of(context).colorScheme.primaryContainer;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var str = 5; str >= 0; str--)
            Row(children: [
              Text(
                '${str == 5 ? tuning[str].toLowerCase() : tuning[str]}|',
                style: tabTextStyle,
              ),
              for (var col = 0; col < line.length; col++) ...[
                if (col > 0 && line.barlines.contains(col))
                  const Text('|', style: tabTextStyle),
                GestureDetector(
                  onTap: () => onTapCell(col, str),
                  child: Container(
                    color: col == cursorCol && str == cursorStr ? highlight : null,
                    child: Text(
                      (line.cellAt(col, str)?.fret ?? '').padRight(widths[col], '-'),
                      style: tabTextStyle,
                    ),
                  ),
                ),
              ],
              const Text('|', style: tabTextStyle),
            ]),
        ],
      ),
    );
  }
}
