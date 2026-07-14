import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'wood_background.dart';

final _urlRe = RegExp(r'https?://\S+');

/// Free-form song notes — practice reminders, tutorial video links, whatever.
/// URLs in the text are tappable. With [onEdit] set (owners), an edit button
/// appears; empty notes render as a subtle "add notes" affordance.
class NotesCard extends StatefulWidget {
  final String notes;
  final VoidCallback? onEdit;

  const NotesCard({super.key, required this.notes, this.onEdit});

  @override
  State<NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<NotesCard> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _linkified(Color linkColor) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlRe.allMatches(widget.notes)) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.notes.substring(last, m.start)));
      }
      final url = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url));
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
        recognizer: recognizer,
      ));
      last = m.end;
    }
    if (last < widget.notes.length) {
      spans.add(TextSpan(text: widget.notes.substring(last)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.notes.isEmpty) {
      if (widget.onEdit == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: WoodLegibleButton(
            onPressed: widget.onEdit!,
            icon: Icons.notes,
            label: 'Add notes / links',
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text.rich(TextSpan(
                style: theme.textTheme.bodyMedium,
                children: _linkified(theme.colorScheme.primary),
              )),
            ),
          ),
          if (widget.onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit notes',
              onPressed: widget.onEdit,
            ),
        ]),
      ),
    );
  }
}
