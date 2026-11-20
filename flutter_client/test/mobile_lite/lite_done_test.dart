import 'package:flutter/material.dart';
import 'package:flutter_client/features/results/rendered_clip.dart';
import 'package:flutter_client/mobile_lite/done_screen.dart';
import 'package:flutter_client/mobile_lite/studio_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves hosted and Rust output URLs without duplicating prefixes', () {
    final base = Uri.parse('https://clippify.example');
    expect(
      liteOutputUri(base, 'output/session/reel.mp4', local: true).toString(),
      'https://clippify.example/api/files/output/session/reel.mp4',
    );
    expect(
      liteOutputUri(base, '/files/output/reel.mp4', local: false).path,
      '/files/output/reel.mp4',
    );
    expect(
      liteOutputUri(
        base,
        'https://cdn.example/reel.mp4?sig=abc',
        local: false,
      ).query,
      'sig=abc',
    );
    expect(
      () => liteOutputUri(base, 'https://cdn.example/reel.mp4', local: true),
      throwsFormatException,
    );
    expect(
      () => liteOutputUri(base, 'file:///C:/reel.mp4', local: false),
      throwsFormatException,
    );
  });

  testWidgets('shows a vertical preview and mobile actions on a small screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Uri? preview;
    var restarted = false;
    const frameKey = ValueKey('preview');
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(ThemeData.dark()),
        builder: (_, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: LiteDoneScreen(
          clips: const [
            RenderedClipData(
              index: 0,
              fileUrl: 'https://cdn.example/reel.mp4',
              viralScore: 0,
              durationSec: 30,
              hasCaptions: false,
            ),
          ],
          previewBuilder: (uri) {
            preview = uri;
            return const ColoredBox(key: frameKey, color: Colors.black);
          },
          onRestart: () => restarted = true,
        ),
      ),
    );

    expect(preview.toString(), 'https://cdn.example/reel.mp4');
    final frame = tester.getSize(find.byKey(frameKey));
    expect(frame.width / frame.height, closeTo(9 / 16, 0.001));
    expect(find.text('احفظ الفيديو').hitTestable(), findsOneWidget);
    expect(find.text('شارك الريل').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('فيديو جديد'));
    expect(restarted, isTrue);
  });
}
