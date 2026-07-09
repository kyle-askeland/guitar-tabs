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

final SongStore store = apiUrl.isEmpty ? LocalStore() : ApiStore(apiUrl);
