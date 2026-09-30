import 'dart:io';

import 'package:flutter_client/core/export/fcp_xml_exporter.dart';
import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_test/flutter_test.dart';

VideoClip clip({
  required String id,
  required String path,
  required double start,
  required double end,
  double trimStart = 0,
  double? trimEnd,
  double sourceDuration = 100,
}) =>
    VideoClip(
      id: id,
      sourcePath: path,
      startTimeInTimeline: start,
      endTimeInTimeline: end,
      sourceTrimStart: trimStart,
      sourceTrimEnd: trimEnd ?? end,
      sourceDuration: sourceDuration,
      transform: TransformState.defaultState(),
      colorGrading: ColorGradingState(),
      filters: const [],
      aiFeatures: AIFeatures(),
    );

TimelineState stateWith({
  List<VideoClip> clips = const [],
  List<SubtitleClip> subtitles = const [],
  int fps = 30,
  String projectName = 'مشروع اختبار',
}) =>
    TimelineState(
      projectId: 'p1',
      projectName: projectName,
      settings: TimelineSettings(width: 1080, height: 1920, fps: fps),
      tracks: Tracks(
        video: [VideoTrack(id: 'v', name: 'V1', index: 0, clips: clips)],
        audio: [],
        subtitles: [SubtitleTrack(id: 'sub', clips: subtitles)],
        overlays: [],
        text: [],
      ),
    );

void main() {
  group('buildFcpXml', () {
    test('produces an FCP7 xmeml v4 skeleton', () {
      final xml = buildFcpXml(
        timeline: stateWith(clips: [
          clip(id: 'c1', path: 'C:/media/a.mp4', start: 0, end: 10),
        ]),
      );
      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<xmeml version="4">'));
      expect(xml, contains('<sequence id="sequence-1">'));
      expect(xml, contains('</xmeml>'));
      expect(xml, contains('<width>1080</width>'));
      expect(xml, contains('<height>1920</height>'));
    });

    test('clip timing is converted to frames', () {
      final xml = buildFcpXml(
        timeline: stateWith(fps: 30, clips: [
          clip(id: 'c1', path: 'C:/media/a.mp4', start: 1, end: 3,
              trimStart: 5, trimEnd: 7, sourceDuration: 100),
        ]),
      );
      expect(xml, contains('<start>30</start>'));
      expect(xml, contains('<end>90</end>'));
      expect(xml, contains('<in>150</in>'));
      expect(xml, contains('<out>210</out>'));
      expect(xml, contains('<duration>3000</duration>'));
    });

    test('duration equals last clip end', () {
      final xml = buildFcpXml(
        timeline: stateWith(clips: [
          clip(id: 'c1', path: 'a.mp4', start: 0, end: 4),
          clip(id: 'c2', path: 'b.mp4', start: 4, end: 12),
        ]),
      );
      expect(xml, contains('<duration>360</duration>'));
    });

    test('pathurl is a proper file URI', () {
      final xml = buildFcpXml(
        timeline: stateWith(clips: [
          clip(id: 'c1', path: 'C:/media/a b.mp4', start: 0, end: 5),
        ]),
      );
      expect(xml, contains('<pathurl>file:///C:/media/a%20b.mp4</pathurl>'));
      expect(xml, contains('<name>a b.mp4</name>'));
    });

    test('one video and one audio clipitem per clip', () {
      final xml = buildFcpXml(
        timeline: stateWith(clips: [
          clip(id: 'c1', path: 'a.mp4', start: 0, end: 5),
          clip(id: 'c2', path: 'b.mp4', start: 5, end: 9),
        ]),
      );
      expect('<clipitem id="clipitem-'.allMatches(xml).length, 2);
      expect('<clipitem id="aclipitem-'.allMatches(xml).length, 2);
      expect(xml, contains('<mediatype>audio</mediatype>'));
    });

    test('subtitles become markers', () {
      final xml = buildFcpXml(
        timeline: stateWith(
          clips: [clip(id: 'c1', path: 'a.mp4', start: 0, end: 10)],
          subtitles: [
            SubtitleClip(
              id: 's1',
              text: 'مرحبا & <عالم>',
              startTime: 1,
              endTime: 2,
              style: SubtitleClipStyle(),
            ),
          ],
        ),
      );
      expect(xml, contains('<markers>'));
      expect(xml, contains('مرحبا &amp; &lt;عالم&gt;'));
      expect(xml, contains('<in>30</in>'));
      expect(xml, contains('<out>60</out>'));
    });

    test('includeMarkers=false omits markers', () {
      final xml = buildFcpXml(
        timeline: stateWith(
          clips: [clip(id: 'c1', path: 'a.mp4', start: 0, end: 10)],
          subtitles: [
            SubtitleClip(
              id: 's1',
              text: 'x',
              startTime: 1,
              endTime: 2,
              style: SubtitleClipStyle(),
            ),
          ],
        ),
        includeMarkers: false,
      );
      expect(xml, isNot(contains('<markers>')));
    });

    test('project name is XML-escaped', () {
      final xml = buildFcpXml(
        timeline: stateWith(projectName: 'A & B'),
        );
      expect(xml, contains('<name>A &amp; B</name>'));
    });
  });

  group('writeFcpXml', () {
    test('writes the file to disk', () async {
      final dir = Directory.systemTemp.createTempSync('clippify_xml_test');
      final out = '${dir.path}\\project.xml';
      final result = await writeFcpXml(
        timeline: stateWith(clips: [
          clip(id: 'c1', path: 'a.mp4', start: 0, end: 5),
        ]),
        outputPath: out,
      );
      expect(result.success, isTrue);
      expect(File(out).existsSync(), isTrue);
      expect(File(out).readAsStringSync(), contains('</xmeml>'));
      dir.deleteSync(recursive: true);
    });

    test('fails on empty timeline', () async {
      final dir = Directory.systemTemp.createTempSync('clippify_xml_test');
      final result = await writeFcpXml(
        timeline: stateWith(),
        outputPath: '${dir.path}\\empty.xml',
      );
      expect(result.success, isFalse);
      expect(result.error, contains('لا توجد مقاطع'));
      dir.deleteSync(recursive: true);
    });
  });
}
