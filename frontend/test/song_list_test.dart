import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/main.dart';
import 'package:guitar_tabs/storage/song_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('search filters only once the Search button is pressed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await store.create('Blackbird');
    await store.create('Wish You Were Here');

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(find.text('TabStash'), findsOneWidget);
    expect(find.text('Blackbird'), findsOneWidget);

    // Typing alone changes nothing — the filter (and, on the API store, any
    // cost) waits for an explicit search.
    await tester.enterText(find.byType(TextField), 'wish');
    await tester.pump();
    expect(find.text('Blackbird'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Blackbird'), findsNothing);
    expect(find.text('Wish You Were Here'), findsOneWidget);
  });

  testWidgets('a delete elsewhere refreshes the open list immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = await store.create('Blackbird');

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(find.text('Blackbird'), findsOneWidget);

    await store.delete(song.songId); // as the editor's delete would
    await tester.pumpAndSettle();
    expect(find.text('Blackbird'), findsNothing);
  });
}
