import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/core/constants/timeline_constants.dart';

void main() {
  group('TimelineConstants', () {
    test('track heights', () {
      expect(TimelineConstants.videoTrackHeight, 78);
      expect(TimelineConstants.audioTrackHeight, 58);
      expect(TimelineConstants.overlayTrackHeight, 48);
      expect(TimelineConstants.subtitleTrackHeight, 38);
      expect(TimelineConstants.textTrackHeight, 50);
      expect(TimelineConstants.nestedTrackHeight, 58);
      expect(TimelineConstants.trackGap, 4);
    });

    test('zoom limits', () {
      expect(TimelineConstants.minZoom, 1.0);
      expect(TimelineConstants.maxZoom, 500.0);
      expect(TimelineConstants.defaultZoom, 30.0);
    });

    test('snap and grid', () {
      expect(TimelineConstants.snapTolerancePixels, 8.0);
      expect(TimelineConstants.gridIntervalSec, 5);
    });

    test('sidebar and playhead', () {
      expect(TimelineConstants.sidebarWidth, 110);
      expect(TimelineConstants.playheadWidth, 2);
    });
  });
}
