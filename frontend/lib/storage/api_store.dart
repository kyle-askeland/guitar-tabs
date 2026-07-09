import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/song.dart';
import 'owner_token.dart';
import 'song_store.dart';

/// Talks to the deployed API (SPECS §4). Whole-document saves,
/// last-write-wins; the owner token rides along on every request.
class ApiStore implements SongStore {
  final String baseUrl;

  ApiStore(this.baseUrl);

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final headers = {
      'x-owner-token': await getOwnerToken(),
      if (body != null) 'content-type': 'application/json',
    };
    final uri = Uri.parse('$baseUrl$path');
    final req = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode >= 400) {
      final message = jsonDecode(res.body)['message'] ?? 'request failed';
      throw Exception('$message (${res.statusCode})');
    }
    return jsonDecode(res.body);
  }

  @override
  Future<List<SongSummary>> list() async => [
        for (final j in await _request('GET', '/songs')) SongSummary.fromJson(j)
      ];

  @override
  Future<Song> fetch(String id) async =>
      Song.fromJson(await _request('GET', '/songs/$id'));

  @override
  Future<Song> create(String title) async =>
      Song.fromJson(await _request('POST', '/songs', body: {'title': title}));

  @override
  Future<void> save(Song song) =>
      _request('PUT', '/songs/${song.songId}', body: song.toJson());

  @override
  Future<void> delete(String id) => _request('DELETE', '/songs/$id');
}
