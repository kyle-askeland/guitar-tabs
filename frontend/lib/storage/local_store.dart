import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'song_store.dart';

/// localStorage persistence via shared_preferences — the zero-AWS store.
/// All local songs are owned by this browser by definition.
class LocalStore implements SongStore {
  Future<Map<String, dynamic>> _readAll(SharedPreferences prefs) async =>
      jsonDecode(prefs.getString('songs') ?? '{}');

  Future<void> _writeAll(SharedPreferences prefs, Map<String, dynamic> all) =>
      prefs.setString('songs', jsonEncode(all));

  @override
  Future<List<SongSummary>> list() async {
    final all = await _readAll(await SharedPreferences.getInstance());
    final songs = [for (final j in all.values) SongSummary.fromJson(j)];
    songs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return songs;
  }

  @override
  Future<Song> fetch(String id) async {
    final all = await _readAll(await SharedPreferences.getInstance());
    final j = all[id];
    if (j == null) throw Exception('song not found');
    return Song.fromJson(j);
  }

  @override
  Future<Song> create(String title) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}'
        '-${Random().nextInt(0xffffff).toRadixString(16)}';
    final song = Song(songId: id, title: title, createdAt: now, updatedAt: now);
    await save(song);
    return song;
  }

  @override
  Future<void> save(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    song.updatedAt = DateTime.now().toUtc().toIso8601String();
    all[song.songId] = song.toJson();
    await _writeAll(prefs, all);
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    all.remove(id);
    await _writeAll(prefs, all);
  }
}
