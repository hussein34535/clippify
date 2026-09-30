import 'dart:convert';
import 'dart:io';

import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/core/services/project_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineState demoTimeline() => TimelineState(
      projectId: 'p1',
      projectName: 'roundtrip',
      settings: TimelineSettings(),
      tracks: Tracks(
        video: [
          VideoTrack(id: 'v', name: 'V', index: 0, clips: [
            VideoClip(
              id: 'c1',
              sourcePath: 'a.mp4',
              startTimeInTimeline: 0,
              endTimeInTimeline: 5,
              sourceTrimStart: 0,
              sourceTrimEnd: 5,
              transform: TransformState.defaultState(),
              colorGrading: ColorGradingState(),
              filters: const [],
              aiFeatures: AIFeatures(),
            ),
          ]),
        ],
        audio: const [],
        subtitles: const [],
        overlays: const [],
        text: const [],
      ),
    );

void main() {
  group('ProjectFileService roundtrip', () {
    test('save → load preserves timeline + comments', () async {
      final svc = ProjectFileService();
      final dir = Directory.systemTemp.createTempSync('clippify_proj_test');
      try {
        final path = '${dir.path}${Platform.pathSeparator}demo.clippify';
        await svc.saveProject(demoTimeline(), path, comments: [
          {'id': 'c1', 'time_sec': 2.0, 'text': 'note', 'created_at': '2026-01-01T00:00:00Z'},
        ]);

        final loaded = await svc.loadProject(path);
        expect(loaded.projectName, 'roundtrip');
        expect(loaded.tracks.video.first.clips, hasLength(1));

        final comments = await svc.loadProjectComments(path);
        expect(comments, hasLength(1));
        expect(comments.first['text'], 'note');
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('legacy bare-timeline files still load, comments empty', () async {
      final svc = ProjectFileService();
      final dir = Directory.systemTemp.createTempSync('clippify_proj_test');
      try {
        final path = '${dir.path}${Platform.pathSeparator}legacy.clippify';
        await File(path).writeAsString(jsonEncode(demoTimeline().toJson()));
        final loaded = await svc.loadProject(path);
        expect(loaded.tracks.video.first.clips, hasLength(1));
        expect(await svc.loadProjectComments(path), isEmpty);
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('corrupt file throws instead of half-loading', () async {
      final svc = ProjectFileService();
      final dir = Directory.systemTemp.createTempSync('clippify_proj_test');
      try {
        final path = '${dir.path}${Platform.pathSeparator}bad.clippify';
        await File(path).writeAsString('not json{{{');
        await expectLater(svc.loadProject(path), throwsA(anything));
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
