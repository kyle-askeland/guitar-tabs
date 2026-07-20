/// One-time (re-runnable) bulk import of vaclavblazej/tabs into the deployed
/// API (see docs/ARCHITECTURE.md, "Import tooling"). Fetches raw `.tab`
/// files directly from raw.githubusercontent.com and parses them with
/// `vaclavblazej_parser.dart` (which reuses the app's own `parseTab`, so this
/// importer doesn't need a second one-off parser).
///
/// Every song is created under a fixed, constant owner token (never
/// regenerated) rather than a fresh UUID per run: that's what makes the
/// import read-only to regular browsers (no matching token exists anywhere
/// else) and gives dedup a natural key on re-runs.
///
/// Usage:
///   cd scripts && flutter pub get   # one-time, resolves the path dep
///   dart run bin/import_vaclavblazej.dart --api-url=https://xxx.execute-api... [--dry-run] [--limit=N]
library;

import 'dart:convert';
import 'dart:io';

import 'package:guitar_tabs/models/song.dart';
import 'package:guitar_tabs_scripts/vaclavblazej_parser.dart';
import 'package:http/http.dart' as http;

/// Fixed forever — this is the whole ownership model (docs/ARCHITECTURE.md):
/// no regular browser holds this token, so imported songs show up in "All"
/// but can't be edited/deleted via the UI, and it doubles as the dedup key
/// on re-runs (`GET /songs` sent with this token → `mine` marks our own).
/// Do not regenerate this if the script is ever run again.
const importOwnerToken = 'a1e26b3e-6b7b-4b1a-9c2b-vaclavblazej-import';

const _repoApi = 'https://api.github.com/repos/vaclavblazej/tabs/contents';

/// english/ + melodies/ + other/ only — czech-slovak/ (different language)
/// and incomplete/ (maintainer-flagged unfinished) are deliberately skipped.
const _defaultDirs = ['english', 'melodies', 'other'];

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final apiUrl = opts['api-url'];
  final dryRun = opts.containsKey('dry-run');
  if (apiUrl == null && !dryRun) {
    stderr.writeln(
        'Usage: dart run bin/import_vaclavblazej.dart --api-url=https://... [--dry-run] [--limit=N] [--dirs=english,melodies,other]');
    exit(1);
  }
  final dirs = (opts['dirs'] ?? _defaultDirs.join(',')).split(',');
  final limit = int.tryParse(opts['limit'] ?? '');

  final client = http.Client();
  var imported = 0, skippedExisting = 0, emptyParse = 0, failed = 0, seen = 0;
  try {
    var existing = <String>{};
    if (!dryRun) {
      existing = await _fetchExistingKeys(client, apiUrl!);
      print('${existing.length} song(s) already imported under the import token.');
    }

    for (final dir in dirs) {
      final files = await _listDir(client, dir);
      for (final file in files) {
        if (limit != null && seen >= limit) break;
        seen++;
        final path = '$dir/$file';
        String raw;
        try {
          raw = await _fetchRaw(client, path);
        } catch (e) {
          stderr.writeln('$path: fetch failed ($e)');
          failed++;
          continue;
        }

        final header = parseHeader(raw);
        final (title, artist) = titleArtistFromFilename(file);
        if (title.isEmpty) {
          stderr.writeln('$path: no title extracted, skipping');
          failed++;
          continue;
        }
        final sections = buildSections(header.body);
        if (sections.isEmpty) {
          stderr.writeln('$path: parsed to zero usable lines, skipping');
          emptyParse++;
          continue;
        }

        final key = dedupKey(title, artist);
        if (existing.contains(key)) {
          print('$path: already imported, skipping');
          skippedExisting++;
          continue;
        }

        final lineCount = sections.fold(0, (n, s) => n + s.lines.length);
        if (dryRun) {
          print('$path: [dry-run] "$title" / "$artist" '
              '(${sections.length} sections, $lineCount lines)');
          imported++;
          continue;
        }

        final song = Song(
          songId: '',
          title: title,
          artist: artist,
          tuning: header.tuning,
          notes: header.notes,
          sections: sections,
        );
        try {
          await _postSong(client, apiUrl!, song);
          print('$path: imported "$title" / "$artist" ($lineCount lines)');
          existing.add(key);
          imported++;
        } catch (e) {
          stderr.writeln('$path: import failed ($e)');
          failed++;
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  } finally {
    client.close();
  }
  print('\nDone. imported=$imported alreadyImported=$skippedExisting '
      'emptyParse=$emptyParse failed=$failed totalSeen=$seen');
  if (failed > 0) exit(1);
}

// ---- CLI / HTTP plumbing ----

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (final a in args) {
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    map[eq < 0 ? a.substring(2) : a.substring(2, eq)] =
        eq < 0 ? 'true' : a.substring(eq + 1);
  }
  return map;
}

/// GitHub's unauthenticated contents API 403s without a User-Agent.
Future<List<String>> _listDir(http.Client client, String dir) async {
  final res = await client.get(Uri.parse('$_repoApi/$dir'),
      headers: {'user-agent': 'guitar-tabs-importer'});
  if (res.statusCode != 200) {
    throw Exception('listing $dir failed: ${res.statusCode}');
  }
  final items = jsonDecode(res.body) as List;
  return [
    for (final it in items)
      if (it['type'] == 'file') it['name'] as String
  ];
}

Future<String> _fetchRaw(http.Client client, String path) async {
  final uri = Uri.https('raw.githubusercontent.com', '/vaclavblazej/tabs/main/$path');
  final res = await client.get(uri);
  if (res.statusCode != 200) {
    throw Exception('raw fetch failed: ${res.statusCode}');
  }
  return res.body;
}

/// Sends the import token as the caller's own identity: `GET /songs`
/// returns `mine: true` for exactly the songs owned by that token, which is
/// the entire dedup mechanism — reuses the ownership token as the natural
/// unique-enough key instead of a separate source-id.
Future<Set<String>> _fetchExistingKeys(http.Client client, String apiUrl) async {
  final res = await client.get(Uri.parse('$apiUrl/songs'),
      headers: {'x-owner-token': importOwnerToken});
  if (res.statusCode != 200) {
    throw Exception('GET /songs failed: ${res.statusCode}');
  }
  final items = jsonDecode(res.body) as List;
  return {
    for (final it in items)
      if (it['mine'] == true) dedupKey(it['title'] ?? '', it['artist'] ?? '')
  };
}

Future<void> _postSong(http.Client client, String apiUrl, Song song) async {
  final res = await client.post(
    Uri.parse('$apiUrl/songs'),
    headers: {'content-type': 'application/json', 'x-owner-token': importOwnerToken},
    body: jsonEncode(song.toJson()),
  );
  if (res.statusCode >= 400) throw Exception('${res.statusCode}: ${res.body}');
}
