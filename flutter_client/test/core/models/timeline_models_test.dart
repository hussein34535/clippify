import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/core/models/timeline_models.dart';

void main() {
  group('Vector2D', () {
    test('toJson encodes correctly', () {
      final v = Vector2D(x: 100, y: 200);
      expect(v.toJson(), {'x': 100.0, 'y': 200.0});
    });

    test('fromJson decodes correctly', () {
      final v = Vector2D.fromJson({'x': 50, 'y': 75});
      expect(v.x, 50.0);
      expect(v.y, 75.0);
    });

    test('copyWith updates only specified fields', () {
      final v = Vector2D(x: 10, y: 20).copyWith(x: 30);
      expect(v.x, 30.0);
      expect(v.y, 20.0);
    });
  });

  group('Keyframe', () {
    test('default easing is linear', () {
      final kf = Keyframe(time: 0, property: 'x', value: 10);
      expect(kf.easing, 'linear');
    });

    test('toJson / fromJson roundtrip', () {
      final original = Keyframe(time: 5, property: 'position_x', value: 100.0, easing: 'ease-out');
      final decoded = Keyframe.fromJson(original.toJson());
      expect(decoded.time, original.time);
      expect(decoded.property, original.property);
      expect(decoded.value, original.value);
      expect(decoded.easing, original.easing);
    });
  });

  group('ColorGradingState', () {
    test('default values', () {
      final cg = ColorGradingState();
      expect(cg.brightness, 0.0);
      expect(cg.contrast, 1.0);
      expect(cg.saturation, 1.0);
      expect(cg.temperature, 0.0);
    });

    test('copyWith', () {
      final cg = ColorGradingState(brightness: 0.5).copyWith(contrast: 1.5);
      expect(cg.brightness, 0.5);
      expect(cg.contrast, 1.5);
      expect(cg.saturation, 1.0);
    });
  });

  group('Transition', () {
    test('available types contain all transitions', () {
      expect(Transition.availableTypes, contains('cross_dissolve'));
      expect(Transition.availableTypes, contains('fade_to_black'));
      expect(Transition.availableTypes, contains('wipe_left'));
      expect(Transition.availableTypes, contains('spin'));
    });

    test('duration defaults to 0.5', () {
      final t = Transition(type: 'cross_dissolve');
      expect(t.duration, 0.5);
    });
  });

  group('TextClip', () {
    test('creates with defaults', () {
      final tc = TextClip(id: '1', text: 'Hello', startTime: 0, endTime: 5);
      expect(tc.fontFamily, 'Roboto');
      expect(tc.fontSize, 48.0);
      expect(tc.alignment, 'center');
    });

    test('toJson / fromJson roundtrip', () {
      final original = TextClip(
        id: 'txt_1', text: 'مرحبا', startTime: 0, endTime: 10,
        fontFamily: 'Arial', fontSize: 32, colorValue: 0xFFFF0000,
        isBold: true,
      );
      final decoded = TextClip.fromJson(original.toJson());
      expect(decoded.text, original.text);
      expect(decoded.fontFamily, original.fontFamily);
      expect(decoded.fontSize, original.fontSize);
      expect(decoded.colorValue, original.colorValue);
      expect(decoded.isBold, original.isBold);
    });
  });

  group('SpeedRamp', () {
    test('empty ramp returns 1.0 speed', () {
      final ramp = SpeedRamp();
      expect(ramp.getSpeedAtTime(5, 10), 1.0);
    });

    test('interpolates between two points', () {
      final ramp = SpeedRamp(points: [
        SpeedPoint(time: 0, speed: 1.0),
        SpeedPoint(time: 10, speed: 2.0),
      ]);
      expect(ramp.getSpeedAtTime(5, 10), closeTo(1.5, 0.01));
      expect(ramp.getSpeedAtTime(0, 10), 1.0);
      expect(ramp.getSpeedAtTime(10, 10), 2.0);
    });

    test('clamps to first/last point', () {
      final ramp = SpeedRamp(points: [
        SpeedPoint(time: 2, speed: 1.0),
        SpeedPoint(time: 8, speed: 3.0),
      ]);
      expect(ramp.getSpeedAtTime(0, 10), 1.0);
      expect(ramp.getSpeedAtTime(10, 10), 3.0);
    });
  });

  group('TimelineState', () {
    test('empty creates valid empty state', () {
      final state = TimelineState.empty();
      expect(state.projectId, 'project_new');
      expect(state.projectName, 'مشروع جديد');
      expect(state.tracks.video.length, 1);
      expect(state.tracks.video[0].clips, isEmpty);
      expect(state.tracks.text.length, 1);
    });

    test('toJson / fromJson roundtrip', () {
      final original = TimelineState.empty();
      final decoded = TimelineState.fromJson(original.toJson());
      expect(decoded.projectId, original.projectId);
      expect(decoded.projectName, original.projectName);
      expect(decoded.playheadSec, original.playheadSec);
      expect(decoded.zoomLevel, original.zoomLevel);
      expect(decoded.tracks.video.length, original.tracks.video.length);
      expect(decoded.tracks.text.length, original.tracks.text.length);
    });

    test('copyWith updates fields', () {
      final state = TimelineState.empty().copyWith(playheadSec: 15.0, zoomLevel: 50.0);
      expect(state.playheadSec, 15.0);
      expect(state.zoomLevel, 50.0);
    });
  });
}
