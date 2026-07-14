import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'api_store.dart';
import 'local_store.dart';

/// Compile-time switch: `--dart-define=API_URL=...` selects the AWS backend,
/// otherwise songs persist in browser localStorage.
const apiUrl = String.fromEnvironment('API_URL');

abstract class SongStore {
  Future<List<SongSummary>> list();
  Future<Song> fetch(String id);
  Future<Song> create(String title);
  Future<void> save(Song song);
  Future<void> delete(String id);
}

/// Bumped after every write. The song list listens, so a save, rename, or
/// delete made in the editor shows up the moment you come back.
final songsChanged = ValueNotifier<int>(0);

/// Wraps the real store to fire [songsChanged]; keeps the notifier out of
/// both store implementations.
class _NotifyingStore implements SongStore {
  final SongStore inner;

  _NotifyingStore(this.inner);

  void _bump() => songsChanged.value++;

  @override
  Future<List<SongSummary>> list() => inner.list();

  @override
  Future<Song> fetch(String id) => inner.fetch(id);

  @override
  Future<Song> create(String title) async {
    final song = await inner.create(title);
    _bump();
    return song;
  }

  @override
  Future<void> save(Song song) async {
    await inner.save(song);
    _bump();
  }

  @override
  Future<void> delete(String id) async {
    await inner.delete(id);
    _bump();
  }
}

final SongStore store =
    _NotifyingStore(apiUrl.isEmpty ? LocalStore() : ApiStore(apiUrl));
