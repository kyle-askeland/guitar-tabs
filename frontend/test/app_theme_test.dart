import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/storage/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the saved mode and defaults to light', () async {
    SharedPreferences.setMockInitialValues({'darkMode': true});
    await loadTheme();
    expect(darkModeNotifier.value, true);

    SharedPreferences.setMockInitialValues({});
    await loadTheme();
    expect(darkModeNotifier.value, false);
  });

  test('setDarkMode persists the choice', () async {
    SharedPreferences.setMockInitialValues({});
    await setDarkMode(true);
    expect(darkModeNotifier.value, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('darkMode'), true);
  });
}
