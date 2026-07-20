/// Lyrics lookup (see docs/ARCHITECTURE.md): fetches plain-text lyrics from
/// lyrics.ovh for a song's artist/title.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches lyrics.ovh for `artist`/`title`. Null on any failure (404,
/// network error, empty body) — treated as "nothing found," not an error
/// state — a lookup failure and a bad alignment both just mean "the preview
/// has nothing/something wrong for the user to fix".
Future<String?> fetchLyrics(String artist, String title) async {
  final uri = Uri.parse(
      'https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}');
  try {
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final text = (jsonDecode(res.body)['lyrics'] as String?)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  } catch (_) {
    return null;
  }
}

/// One artist/title candidate from lyrics.ovh's `/suggest` endpoint (a thin
/// wrapper over Deezer's track search). [fetchLyrics] needs an exact
/// artist/title match and does no fuzzy matching of its own — a typo just
/// comes back "not found" — so this is the actual help for misspellings:
/// Deezer's search tolerates them and returns the correct spelling.
class SongSuggestion {
  final String artist;
  final String title;
  SongSuggestion(this.artist, this.title);
}

/// Live search-as-you-type suggestions for `query` (free text, e.g. "oassis
/// wondrwall"). Empty on any failure or a blank query — same
/// nothing-to-show-on-failure approach as [fetchLyrics]. Deduplicated by
/// artist+title and capped at 6 — Deezer often returns the same track
/// several times over (different releases/remasters).
Future<List<SongSuggestion>> suggestSongs(String query) async {
  final q = query.trim();
  if (q.isEmpty) return [];
  final uri =
      Uri.parse('https://api.lyrics.ovh/suggest/${Uri.encodeComponent(q)}');
  try {
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body)['data'] as List?;
    if (data == null) return [];
    final seen = <String>{};
    final out = <SongSuggestion>[];
    for (final t in data) {
      final artist = t['artist']?['name'] as String?;
      final title = t['title'] as String?;
      if (artist == null || title == null) continue;
      if (seen.add('$artist|$title')) out.add(SongSuggestion(artist, title));
      if (out.length >= 6) break;
    }
    return out;
  } catch (_) {
    return [];
  }
}
