import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/shared/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('L10n keysets — ar/en parity', () {
    test('same keyset in BOTH directions (fails with missing-key lists)', () {
      final missingInEn =
          L10n.ar.keys.where((k) => !L10n.en.containsKey(k)).toList()..sort();
      final missingInAr =
          L10n.en.keys.where((k) => !L10n.ar.containsKey(k)).toList()..sort();
      expect(missingInEn, isEmpty,
          reason: 'keys present in ar but MISSING in en: $missingInEn');
      expect(missingInAr, isEmpty,
          reason: 'keys present in en but MISSING in ar: $missingInAr');
    });

    test('every value is non-empty in both locales', () {
      for (final e in L10n.ar.entries) {
        expect(e.value.trim(), isNotEmpty, reason: 'ar[${e.key}] is empty');
      }
      for (final e in L10n.en.entries) {
        expect(e.value.trim(), isNotEmpty, reason: 'en[${e.key}] is empty');
      }
    });
  });

  group('L10n.t()', () {
    const ar = L10n(Locale('ar'));
    const en = L10n(Locale('en'));

    test('returns the Arabic literal for a known key', () {
      expect(ar.t('common_cancel'), 'إلغاء');
      expect(ar.t('wizard_title'), '🪄 المونتاج التلقائي الذكي');
    });

    test('returns English for en locale', () {
      expect(en.t('common_cancel'), 'Cancel');
      expect(en.t('results_title'), '🎬 Viral Results');
    });

    test('unknown key falls back to the key ITSELF (both locales)', () {
      expect(ar.t('no_such_key_xyz'), 'no_such_key_xyz');
      expect(en.t('no_such_key_xyz'), 'no_such_key_xyz');
    });

    test('tf() substitutes {tokens}', () {
      expect(
        ar.tf('results_saved_toast', {'name': 'clip_1.mp4'}),
        'تم حفظ: clip_1.mp4 ✅',
      );
      expect(
        en.tf('results_added_many_toast', {'n': '3'}),
        'Added 3 clips to the timeline 🎬',
      );
    });
  });

  group('localeProvider persistence', () {
    test('roundtrip: set en → new provider loads en from mocked prefs',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c1.read(localeProvider).pref, LanguagePref.arabic); // default
      expect(c1.read(localeProvider).resolved.languageCode, 'ar');

      await c1.read(localeProvider.notifier).setLanguage(LanguagePref.english);
      expect(c1.read(localeProvider).resolved.languageCode, 'en');

      // Fresh container (fresh notifier) must read persisted value back.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(localeProvider); // wake the lazy notifier
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c2.read(localeProvider).pref, LanguagePref.english);
      expect(c2.read(localeProvider).resolved.languageCode, 'en');

      final stored =
          (await SharedPreferences.getInstance()).getString('clippify_locale');
      expect(stored, 'en');
    });

    test("stored string mapping: null/'ar'→arabic, 'en'→english, 'system'",
        () {
      expect(LocaleNotifier.prefFromStored(null), LanguagePref.arabic);
      expect(LocaleNotifier.prefFromStored('ar'), LanguagePref.arabic);
      expect(LocaleNotifier.prefFromStored('en'), LanguagePref.english);
      expect(LocaleNotifier.prefFromStored('system'), LanguagePref.system);

      expect(LocaleNotifier.prefToStored(LanguagePref.arabic), 'ar');
      expect(LocaleNotifier.prefToStored(LanguagePref.english), 'en');
      expect(LocaleNotifier.prefToStored(LanguagePref.system), 'system');
    });

    test('system pref roundtrips through prefs without throwing', () async {
      SharedPreferences.setMockInitialValues({'clippify_locale': 'system'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(localeProvider); // wake the lazy notifier
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(localeProvider).pref, LanguagePref.system);
      // Resolved locale is always one of the two supported ones.
      expect(['ar', 'en'], contains(c.read(localeProvider).resolved.languageCode));
    });
  });

  group('LanguageToggleRow', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      ProviderContainer? captured;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(child: LanguageToggleRow()),
              ),
            ),
          ),
        ),
      );
      captured = ProviderScope.containerOf(
        tester.element(find.byType(LanguageToggleRow)),
        listen: false,
      );
      return captured;
    }

    testWidgets('tapping English switches the provider to english',
        (tester) async {
      final container = await pump(tester);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('lang_en')));
      await tester.pump();

      expect(container.read(localeProvider).pref, LanguagePref.english);
      expect(container.read(localeProvider).resolved.languageCode, 'en');
    });

    testWidgets('tapping العربية switches back to arabic', (tester) async {
      final container = await pump(tester);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('lang_en')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lang_ar')));
      await tester.pump();

      expect(container.read(localeProvider).pref, LanguagePref.arabic);
      expect(container.read(localeProvider).resolved.languageCode, 'ar');
    });

    testWidgets('tapping النظام selects system-follow', (tester) async {
      final container = await pump(tester);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('lang_system')));
      await tester.pump();

      expect(container.read(localeProvider).pref, LanguagePref.system);
    });
  });
}
