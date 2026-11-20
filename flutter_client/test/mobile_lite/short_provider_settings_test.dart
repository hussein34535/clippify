import 'package:flutter/material.dart';
import 'package:flutter_client/mobile_lite/short_provider_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final modelField = find.widgetWithText(TextField, 'الموديل');
  final endpointField = find.widgetWithText(
    TextField,
    'عنوان المزوّد (Base URL)',
  );
  final keyField = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.obscureText,
  );
  final optIn = find.byType(SwitchListTile);

  test('a legacy key without a stored URL keeps its original provider', () async {
    FlutterSecureStorage.setMockInitialValues({
      'clippify_short_teamsoclo_settings':
          '{"apiKey":"legacy-fixture","model":"legacy-model","cloudEnabled":true}',
    });
    final env = await ShortProviderSettings.loadLaunchEnvironment();
    expect(env['CLIPPIFY_SHORT_AI_BASE_URL'], 'https://gpt.teamsoclo.site/v1');
    expect(env['CLIPPIFY_SHORT_AI_VISION'], isNull);
  });

  test(
    'invalid stored endpoints cannot send a key to the default provider',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'clippify_short_teamsoclo_settings':
            '{"apiKey":"test-token","model":"test-model","cloudEnabled":true,"endpoint":"http://provider.example/v1"}',
      });
      expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);
    },
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ShortProviderSettingsScreen(key: UniqueKey())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'حفظ');
    // The settings list lazily builds its children; scroll to the action row
    // instead of assuming it is already on screen.
    await tester.scrollUntilVisible(
      button,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('requires a saved key and explicit opt-in to export settings', (
    tester,
  ) async {
    await openSettings(tester);
    expect(
      tester.widget<TextField>(endpointField).controller!.text,
      'https://coarena.ai/api/v1',
    );
    expect(find.textContaining('مقتطفات من النص'), findsOneWidget);
    expect(
      tester.widget<TextField>(modelField).controller!.text,
      'deepseek-v4-1-flash-1017',
    );
    expect(tester.widget<SwitchListTile>(optIn).value, isFalse);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);

    await tester.tap(optIn);
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('أدخل مفتاح API للمزوّد المختار.'), findsOneWidget);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);

    await tester.enterText(keyField, ' example-test-token ');
    await save(tester);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);

    await openSettings(tester);
    expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);
    expect(find.text('يوجد مفتاح محفوظ.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(optIn).value, isFalse);

    await tester.tap(optIn);
    await tester.pumpAndSettle();
    await save(tester);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), {
      'CLIPPIFY_SHORT_TEAMSOCLO_KEY': 'example-test-token',
      'CLIPPIFY_SHORT_TEAMSOCLO_MODEL': 'deepseek-v4-1-flash-1017',
      'CLIPPIFY_SHORT_AI_BASE_URL': 'https://coarena.ai/api/v1',
    });

    await tester.tap(optIn);
    await tester.pumpAndSettle();
    await save(tester);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);
    expect(find.text('يوجد مفتاح محفوظ.'), findsOneWidget);
  });

  testWidgets('changing providers never reuses the previous key', (
    tester,
  ) async {
    await openSettings(tester);
    await tester.enterText(keyField, 'test-token');
    await tester.tap(optIn);
    await tester.pumpAndSettle();
    await save(tester);
    await tester.enterText(endpointField, 'https://provider.example/v1');
    await save(tester);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);

    await tester.enterText(keyField, 'new-provider-token');
    await tester.tap(optIn);
    await tester.pumpAndSettle();
    await save(tester);
    expect(await ShortProviderSettings.loadLaunchEnvironment(), {
      'CLIPPIFY_SHORT_TEAMSOCLO_KEY': 'new-provider-token',
      'CLIPPIFY_SHORT_TEAMSOCLO_MODEL': 'deepseek-v4-1-flash-1017',
      'CLIPPIFY_SHORT_AI_BASE_URL': 'https://provider.example/v1',
    });
  });

  testWidgets(
    'keeps the saved input blank and supports replacement and removal',
    (tester) async {
      await openSettings(tester);
      await tester.enterText(keyField, 'example-first-token');
      await tester.tap(optIn);
      await tester.pumpAndSettle();
      await save(tester);
      expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);

      await openSettings(tester);
      expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);
      expect(tester.widget<SwitchListTile>(optIn).value, isTrue);
      await tester.enterText(modelField, ' example-model ');
      await tester.enterText(keyField, 'example-replacement-token');
      await save(tester);

      expect(await ShortProviderSettings.loadLaunchEnvironment(), {
        'CLIPPIFY_SHORT_TEAMSOCLO_KEY': 'example-replacement-token',
        'CLIPPIFY_SHORT_TEAMSOCLO_MODEL': 'example-model',
        'CLIPPIFY_SHORT_AI_BASE_URL': 'https://coarena.ai/api/v1',
      });

      await tester.tap(find.widgetWithText(OutlinedButton, 'إزالة المفتاح'));
      await tester.pumpAndSettle();
      expect(await ShortProviderSettings.loadLaunchEnvironment(), isEmpty);

      await openSettings(tester);
      expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);
      expect(tester.widget<SwitchListTile>(optIn).value, isFalse);
      expect(find.text('يوجد مفتاح محفوظ.'), findsNothing);
      expect(
        tester.widget<TextField>(modelField).controller!.text,
        'example-model',
      );
    },
  );
}
