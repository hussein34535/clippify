import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AG-4 [UIPolish] — guards the Arabic label fixes in the Inspector.
///
/// These tests read the inspector source directly so that a regression
/// (re-introducing the awkward "التحول" literal or mixed Arabic/English
/// slider labels like "الموقع (Position)") fails CI immediately.
void main() {
  const inspectorPath =
      'lib/features/inspector/widgets/inspector_widget.dart';
  late String source;

  setUpAll(() {
    final f = File(inspectorPath);
    expect(f.existsSync(), isTrue,
        reason: 'expected $inspectorPath to exist');
    source = f.readAsStringSync();
  });

  group('Inspector Arabic label polish', () {
    test('no awkward "التحول" literal anywhere (use "التحويل")', () {
      expect(source.contains('التحول'), isFalse,
          reason:
              '"التحول" is the literal translation of Transform and looks '
              'wrong in the UI — use "التحويل" instead');
    });

    test('transform tab uses the correct "التحويل" label', () {
      expect(source.contains("Tab(text: 'التحويل')"), isTrue);
    });

    test('slider section headers drop English parentheticals', () {
      for (final bad in const ['(Position)', '(Scale)', '(Rotation)']) {
        expect(source.contains(bad), isFalse,
            reason: 'mixed Arabic+English label "$bad" found — keep Arabic only');
      }
    });

    test('clean Arabic section headers exist', () {
      expect(source.contains("InspectorSectionHeader(title: 'الموقع')"),
          isTrue, reason: 'missing clean header الموقع');
      expect(source.contains("InspectorSectionHeader(title: 'القياس')"),
          isTrue, reason: 'missing clean header القياس');
      expect(source.contains("InspectorSectionHeader(title: 'الدوران')"),
          isTrue, reason: 'missing clean header الدوران');
    });

    test('keyframes section header is Arabic-only', () {
      expect(source.contains("'Keyframes (مخطط الحركة)'"), isFalse);
      expect(source.contains("InspectorSectionHeader(title: 'مخطط الحركة')"),
          isTrue);
    });

    test('AI tab has no English-only "Viral" label', () {
      expect(source.contains("Tab(text: 'Viral')"), isFalse,
          reason: 'use the Arabic label "ترند"');
    });
  });
}
