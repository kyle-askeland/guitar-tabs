import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Anonymous ownership token (SPECS §7): generated on first visit, sent as
/// `x-owner-token` on API calls. The settings screen exposes it for copying
/// to another device.
Future<String> getOwnerToken() async {
  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString('ownerToken');
  if (token == null) {
    final rng = Random.secure();
    token = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
    await prefs.setString('ownerToken', token);
  }
  return token;
}

Future<void> setOwnerToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ownerToken', token.trim());
}
