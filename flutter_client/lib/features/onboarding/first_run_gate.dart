import 'package:shared_preferences/shared_preferences.dart';

class FirstRunGate {
  static const String seenKey = 'clippify_onboarded_v1';

  const FirstRunGate._();

  static bool shouldShow(SharedPreferences prefs) =>
      !prefs.getKeys().contains(seenKey);

  static Future<void> markSeen(SharedPreferences prefs) =>
      prefs.setBool(seenKey, true);

  /// Clear the seen flag so the onboarding shows again
  /// (used by "إعادة عرض الشرح" in Settings).
  static Future<void> reset(SharedPreferences prefs) =>
      prefs.remove(seenKey);
}
