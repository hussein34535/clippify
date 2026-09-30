import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/timeline_models.dart';
import '../services/services.dart';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _displayFormat(int fps) {
  switch (fps) {
    case 23:
    case 24:
      return '24 fps Non Drop';
    case 25:
      return '25 fps Non Drop';
    case 50:
    case 60:
      return '60 fps Non Drop';
    case 30:
    default:
      return '30 fps Non Drop';
  }
}

/// منهل FCP7 XML (‎`xmeml v4`) — يُستورد في DaVinci Resolve وPremiere Pro
/// مباشرة. بديل محلي لـ `/project/export/xml` الـ501.
///
/// - مسار فيديو واحد (tracks.video[0]) كما في المعاينة.
/// - الترجمات تُصدَّر كـ markers داخل التسلسل (عند [includeMarkers]).
String buildFcpXml({
  required TimelineState timeline,
  bool includeMarkers = true,
}) {
  final fps = timeline.settings.fps > 0 ? timeline.settings.fps : 30;
  final width = timeline.settings.width;
  final height = timeline.settings.height;
  final rate =
      '<rate><timebase>$fps</timebase><ntsc>FALSE</ntsc></rate>';

  final videoTracks = timeline.tracks.video;
  final clips = videoTracks.isEmpty
      ? <VideoClip>[]
      : [...videoTracks.first.clips]
        ..sort((a, b) => a.startTimeInTimeline.compareTo(b.startTimeInTimeline));

  var durationFrames = 0;
  for (final c in clips) {
    final end = (c.endTimeInTimeline * fps).round();
    if (end > durationFrames) durationFrames = end;
  }

  final fileIds = <String, String>{};
  String fileIdFor(String path) =>
      fileIds.putIfAbsent(path, () => 'file-${fileIds.length + 1}');

  final sb = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!DOCTYPE xmeml>')
    ..writeln('<xmeml version="4">')
    ..writeln('  <sequence id="sequence-1">')
    ..writeln('    <name>${_esc(timeline.projectName)}</name>')
    ..writeln('    <duration>$durationFrames</duration>')
    ..writeln('    <rate>$rate</rate>')
    ..writeln(
        '    <timecode><string>00:00:00:00</string><frame>0</frame>'
        '<displayFormat>${_displayFormat(fps)}</displayFormat><rate>$rate</rate></timecode>')
    ..writeln('    <in>-1</in>')
    ..writeln('    <out>-1</out>')
    ..writeln('    <media>')
    ..writeln('      <video>')
    ..writeln(
        '        <format><samplecharacteristics><rate>$rate</rate>'
        '<width>$width</width><height>$height</height></samplecharacteristics></format>')
    ..writeln('        <track>')
    ..writeln('          <enabled>TRUE</enabled>');

  for (var i = 0; i < clips.length; i++) {
    final clip = clips[i];
    final start = (clip.startTimeInTimeline * fps).round();
    final end = (clip.endTimeInTimeline * fps).round();
    final srcIn = (clip.sourceTrimStart * fps).round();
    final srcOut = (clip.sourceTrimEnd * fps).round();
    final srcDur = (clip.sourceDuration * fps).round();
    final fid = fileIdFor(clip.sourcePath);
    final name = p.basename(clip.sourcePath);
    final uri = Uri.file(clip.sourcePath).toString();
    sb
      ..writeln('          <clipitem id="clipitem-${i + 1}">')
      ..writeln('            <name>${_esc(name)}</name>')
      ..writeln('            <enabled>TRUE</enabled>')
      ..writeln('            <duration>$srcDur</duration>')
      ..writeln('            <rate>$rate</rate>')
      ..writeln('            <start>$start</start>')
      ..writeln('            <end>$end</end>')
      ..writeln('            <in>$srcIn</in>')
      ..writeln('            <out>$srcOut</out>')
      ..writeln('            <file id="$fid">')
      ..writeln('              <name>${_esc(name)}</name>')
      ..writeln('              <pathurl>${_esc(uri)}</pathurl>')
      ..writeln('              <rate>$rate</rate>')
      ..writeln('              <duration>$srcDur</duration>')
      ..writeln('              <media>')
      ..writeln(
          '                <video><samplecharacteristics><rate>$rate</rate>'
          '<width>$width</width><height>$height</height></samplecharacteristics></video>')
      ..writeln(
          '                <audio><samplecharacteristics><depth>16</depth>'
          '<samplerate>48000</samplerate></samplecharacteristics><channelcount>2</channelcount></audio>')
      ..writeln('              </media>')
      ..writeln('            </file>')
      // تأثيرات لون/تسريع تبقى للمستقبِل — XML الأساسي ينقل القصّ والتوقيت.
      ..writeln('          </clipitem>');
  }

  sb
    ..writeln('        </track>')
    ..writeln('      </video>')
    ..writeln('      <audio>')
    ..writeln(
        '        <format><samplecharacteristics><depth>16</depth>'
        '<samplerate>48000</samplerate></samplecharacteristics></format>')
    ..writeln('        <track>')
    ..writeln('          <enabled>TRUE</enabled>');

  for (var i = 0; i < clips.length; i++) {
    final clip = clips[i];
    final start = (clip.startTimeInTimeline * fps).round();
    final end = (clip.endTimeInTimeline * fps).round();
    final srcIn = (clip.sourceTrimStart * fps).round();
    final srcOut = (clip.sourceTrimEnd * fps).round();
    final srcDur = (clip.sourceDuration * fps).round();
    final fid = fileIdFor(clip.sourcePath);
    final name = p.basename(clip.sourcePath);
    sb
      ..writeln('          <clipitem id="aclipitem-${i + 1}">')
      ..writeln('            <name>${_esc(name)}</name>')
      ..writeln('            <enabled>TRUE</enabled>')
      ..writeln('            <duration>$srcDur</duration>')
      ..writeln('            <rate>$rate</rate>')
      ..writeln('            <start>$start</start>')
      ..writeln('            <end>$end</end>')
      ..writeln('            <in>$srcIn</in>')
      ..writeln('            <out>$srcOut</out>')
      ..writeln('            <file id="$fid"/>')
      ..writeln(
          '            <sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack>')
      ..writeln('          </clipitem>');
  }

  sb
    ..writeln('        </track>')
    ..writeln('      </audio>')
    ..writeln('    </media>');

  if (includeMarkers) {
    final subs = <SubtitleClip>[];
    for (final track in timeline.tracks.subtitles) {
      subs.addAll(track.clips);
    }
    subs.sort((a, b) => a.startTime.compareTo(b.startTime));
    if (subs.isNotEmpty) {
      sb.writeln('    <markers>');
      for (final s in subs) {
        final inFrame = (s.startTime * fps).round();
        final outFrame = (s.endTime * fps).round();
        sb
          ..writeln('      <marker>')
          ..writeln('        <name>${_esc(s.text)}</name>')
          ..writeln('        <comment>${_esc(s.text)}</comment>')
          ..writeln('        <in>$inFrame</in>')
          ..writeln('        <out>$outFrame</out>')
          ..writeln('        <duration>0</duration>')
          ..writeln('      </marker>');
      }
      sb.writeln('    </markers>');
    }
  }

  sb
    ..writeln('  </sequence>')
    ..writeln('</xmeml>');
  return sb.toString();
}

/// كتابة ملف XML على القرص.
Future<ExportResult> writeFcpXml({
  required TimelineState timeline,
  required String outputPath,
  bool includeMarkers = true,
}) async {
  try {
    if (timeline.tracks.video.isEmpty ||
        timeline.tracks.video.first.clips.isEmpty) {
      return ExportResult(success: false, error: 'لا توجد مقاطع على التايملاين.');
    }
    final dir = p.dirname(outputPath);
    if (dir.isNotEmpty) await Directory(dir).create(recursive: true);
    await File(outputPath).writeAsString(
      buildFcpXml(timeline: timeline, includeMarkers: includeMarkers),
      flush: true,
    );
    return ExportResult(success: true, outputPath: outputPath);
  } catch (e) {
    return ExportResult(success: false, error: e.toString());
  }
}
