import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/constants/timeline_constants.dart';
import '../../../core/storage/local_storage.dart';

class TimelineStateData {
  final TimelineState timeline;
  final List<TimelineState> undoStack;
  final List<TimelineState> redoStack;
  final Set<String> selectedClipIds;
  /// True after any content edit since the last save/load. Playhead and zoom
  /// moves never set it (they don't touch the undo stack).
  final bool isDirty;

  TimelineStateData({
    required this.timeline,
    required this.undoStack,
    required this.redoStack,
    this.selectedClipIds = const {},
    this.isDirty = false,
  });

  TimelineStateData copyWith({
    TimelineState? timeline,
    List<TimelineState>? undoStack,
    List<TimelineState>? redoStack,
    Set<String>? selectedClipIds,
    bool? isDirty,
  }) {
    return TimelineStateData(
      timeline: timeline ?? this.timeline,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      selectedClipIds: selectedClipIds ?? this.selectedClipIds,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  /// Clears the dirty flag after a successful save.
  TimelineStateData asSaved() => copyWith(isDirty: false);
}

class TimelineNotifier extends StateNotifier<TimelineStateData> {
  static const int maxStackSize = 50;
  Timer? _autosaveTimer;

  TimelineNotifier()
      : super(TimelineStateData(
          timeline: TimelineState.empty(),
          undoStack: [],
          redoStack: [],
          selectedClipIds: const {},
        ));

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  /// حفظ تلقائي مع debounce (2 ثانية من آخر تعديل)
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), () {
      LocalStorage().saveAutosave(state.timeline.toJson());
    });
  }

  // ── Gesture sessions ──────────────────────────────────────────────────
  // A drag fires dozens/hundreds of mutations (one per pointer move). We push
  // a SINGLE undo checkpoint (the state before the first mutation) when the
  // gesture starts, then skip further pushes until it ends — otherwise one
  // drag fills the whole undo stack and Ctrl+Z becomes useless.
  int _gestureDepth = 0;
  bool _gestureCheckpointPushed = false;

  void beginGesture() {
    if (_gestureDepth == 0) _gestureCheckpointPushed = false;
    _gestureDepth++;
  }

  void endGesture() {
    if (_gestureDepth > 0) _gestureDepth--;
    if (_gestureDepth == 0) _gestureCheckpointPushed = false;
  }

  /// تسجيل الحالة الحالية في الـ Undo stack قبل أي تعديل
  void _saveToUndoStack() {
    _scheduleAutosave();
    if (!state.isDirty) {
      state = state.copyWith(isDirty: true);
    }
    if (_gestureDepth > 0) {
      // Inside a drag: only the very first mutation pushes the checkpoint.
      if (_gestureCheckpointPushed) return;
      _gestureCheckpointPushed = true;
    }
    final currentHistory = List<TimelineState>.from(state.undoStack);
    if (currentHistory.length >= maxStackSize) {
      currentHistory.removeAt(0);
    }
    // نقوم بحفظ نسخة عميقة (أو مرجعية بما أن الفئات غير قابلة للتغيير بشكل مباشر immutable)
    currentHistory.add(state.timeline);

    state = state.copyWith(
      undoStack: currentHistory,
      redoStack: [], // مسح الـ Redo stack بعد أي تعديل جديد
      isDirty: true,
    );
  }

  /// يُستدعى بعد حفظ ناجح لمسح مؤشر "تغييرات غير محفوظة".
  void markSaved() {
    if (state.isDirty) state = state.asSaved();
  }

  /// التراجع (Undo)
  void undo() {
    if (state.undoStack.isEmpty) return;

    final currentUndoStack = List<TimelineState>.from(state.undoStack);
    final previousState = currentUndoStack.removeLast();

    final currentRedoStack = List<TimelineState>.from(state.redoStack);
    currentRedoStack.add(state.timeline);

    state = state.copyWith(
      timeline: previousState,
      undoStack: currentUndoStack,
      redoStack: currentRedoStack,
    );
  }

  /// الإعادة (Redo)
  void redo() {
    if (state.redoStack.isEmpty) return;

    final currentRedoStack = List<TimelineState>.from(state.redoStack);
    final nextState = currentRedoStack.removeLast();

    final currentUndoStack = List<TimelineState>.from(state.undoStack);
    currentUndoStack.add(state.timeline);

    state = state.copyWith(
      timeline: nextState,
      undoStack: currentUndoStack,
      redoStack: currentRedoStack,
    );
  }

  bool get canUndo => state.undoStack.isNotEmpty;
  bool get canRedo => state.redoStack.isNotEmpty;

  /// تحميل مشروع كامل
  void loadProject(TimelineState newProject) {
    state = TimelineStateData(
      timeline: newProject,
      undoStack: [],
      redoStack: [],
    );
    _scheduleAutosave();
  }

  /// تحديث حالة التايملاين بالكامل مع حفظ الـ Undo stack
  void updateTimelineState(TimelineState newProject) {
    _saveToUndoStack();
    state = state.copyWith(
      timeline: newProject,
    );
  }


  /// تحديث موضع مؤشر القراءة (Playhead) بدون حفظ للتراجع
  void setPlayhead(double timeSec) {
    // Sanitize: playhead must stay within sane project bounds. This makes the
    // "20:00:00:18" class of bugs impossible even if a caller misconverts
    // pixels/frames/milliseconds into seconds.
    final double ceiling = totalDuration > 0 ? totalDuration + 3600 : 3600.0;
    state = state.copyWith(
      timeline: state.timeline.copyWith(playheadSec: timeSec.clamp(0.0, ceiling)),
    );
  }

  /// تحديث مستوى التكبير/التصغير (Zoom) بدون حفظ للتراجع
  void setZoom(double zoom) {
    state = state.copyWith(
      timeline: state.timeline.copyWith(zoomLevel: zoom.clamp(TimelineConstants.minZoom, TimelineConstants.maxZoom)),
    );
  }

  /// تحديث إعدادات المشروع (Aspect Ratio، إلخ)
  void updateSettings(TimelineSettings Function(TimelineSettings) updateFn) {
    _saveToUndoStack();
    final newSettings = updateFn(state.timeline.settings);
    state = state.copyWith(
      timeline: state.timeline.copyWith(settings: newSettings),
    );
  }

  /// إضافة كليب فيديو
  void addVideoClip(VideoClip clip, {int trackIndex = 0}) {
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final videoTracks = List<VideoTrack>.from(currentTracks.video);

    if (trackIndex >= videoTracks.length) {
      videoTracks.add(VideoTrack(
        id: 'v_track_${videoTracks.length}',
        name: 'Video ${videoTracks.length + 1}',
        index: videoTracks.length,
        clips: [],
      ));
    }

    final targetTrack = videoTracks[trackIndex];
    final updatedClips = List<VideoClip>.from(targetTrack.clips)..add(clip);
    
    // ترتيب الكليبات بناءً على وقت البدء
    updatedClips.sort((a, b) => a.startTimeInTimeline.compareTo(b.startTimeInTimeline));

    videoTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(video: videoTracks),
      ),
    );
  }

  /// إضافة كليب صوتي
  void addAudioClip(AudioClip clip, {int trackIndex = 0}) {
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final audioTracks = List<AudioTrack>.from(currentTracks.audio);

    if (trackIndex >= audioTracks.length) {
      audioTracks.add(AudioTrack(
        id: 'a_track_${audioTracks.length}',
        name: 'Audio ${audioTracks.length + 1}',
        index: audioTracks.length,
        clips: [],
      ));
    }

    final targetTrack = audioTracks[trackIndex];
    final updatedClips = List<AudioClip>.from(targetTrack.clips)..add(clip);
    updatedClips.sort((a, b) => a.startTimeInTimeline.compareTo(b.startTimeInTimeline));
    audioTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(audio: audioTracks),
      ),
    );
  }

  /// إضافة تراكب (Overlay)
  void addOverlayClip(OverlayClip clip, {int trackIndex = 0}) {
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final overlayTracks = List<OverlayTrack>.from(currentTracks.overlays);

    if (trackIndex >= overlayTracks.length) {
      overlayTracks.add(OverlayTrack(
        id: 'o_track_${overlayTracks.length}',
        clips: [],
      ));
    }

    final targetTrack = overlayTracks[trackIndex];
    final updatedClips = List<OverlayClip>.from(targetTrack.clips)..add(clip);
    updatedClips.sort((a, b) => a.startTimeInTimeline.compareTo(b.startTimeInTimeline));
    overlayTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(overlays: overlayTracks),
      ),
    );
  }

  /// إضافة نص
  void addTextClip(TextClip clip, {int trackIndex = 0}) {
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final textTracks = List<TextTrack>.from(currentTracks.text);

    if (trackIndex >= textTracks.length) {
      textTracks.add(TextTrack(
        id: 'txt_track_${textTracks.length}',
        clips: [],
      ));
    }

    final targetTrack = textTracks[trackIndex];
    final updatedClips = List<TextClip>.from(targetTrack.clips)..add(clip);
    updatedClips.sort((a, b) => a.startTime.compareTo(b.startTime));
    textTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(text: textTracks),
      ),
    );
  }

  /// تحديث نص
  void updateTextClip(String clipId, TextClip Function(TextClip) updater) {
    final currentTracks = state.timeline.tracks;
    final textTracks = List<TextTrack>.from(currentTracks.text);

    bool found = false;
    for (int i = 0; i < textTracks.length; i++) {
      final track = textTracks[i];
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex != -1) {
        final updatedClips = List<TextClip>.from(track.clips);
        updatedClips[clipIndex] = updater(updatedClips[clipIndex]);
        textTracks[i] = track.copyWith(clips: updatedClips);
        found = true;
        break;
      }
    }
    if (!found) return;
    _saveToUndoStack();

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(text: textTracks),
      ),
    );
  }

  /// حذف نص
  void removeTextClip(String clipId) {
    final currentTracks = state.timeline.tracks;
    final textTracks = List<TextTrack>.from(currentTracks.text);

    bool found = false;
    for (int i = 0; i < textTracks.length; i++) {
      final track = textTracks[i];
      final updatedClips = track.clips.where((c) => c.id != clipId).toList();
      if (updatedClips.length != track.clips.length) {
        textTracks[i] = track.copyWith(clips: updatedClips);
        found = true;
        break;
      }
    }
    if (!found) return;
    _saveToUndoStack();

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(text: textTracks),
      ),
    );
  }

  void _removeClipFromTrack(String clipId, int trackIndex,
      List<dynamic> Function(Tracks) getTracks,
      Tracks Function(Tracks, List<dynamic>) setTracks) {
    final tracks = getTracks(state.timeline.tracks);
    if (trackIndex >= tracks.length) return;
    final updated = tracks[trackIndex].clips.where((c) => c.id != clipId).toList();
    final copy = List<dynamic>.from(tracks);
    copy[trackIndex] = tracks[trackIndex].copyWith(clips: updated);
    state = state.copyWith(
      timeline: state.timeline.copyWith(tracks: setTracks(state.timeline.tracks, copy)),
    );
  }

  /// المسار الذي يحوي [clipId] ضمن قائمة مسارات [getTracks] (‎-1 إذا لم يُوجد).
  /// يمنع الفشل الصامت عندما يكون الكليب على مسارٍ غير الصفر — مثل
  /// [moveVideoClip] يُستنتج تلقائيًا عندما لا يُمرَّر [trackIndex].
  int _locateClipTrack(
      String clipId, List<dynamic> Function(Tracks) getTracks) {
    final tracks = getTracks(state.timeline.tracks);
    return tracks.indexWhere((t) => t.clips.any((c) => c.id == clipId));
  }

  void removeVideoClip(String clipId, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.video);
    if (ti < 0) return;
    _saveToUndoStack();
    _removeClipFromTrack(clipId, ti,
      (t) => t.video,
      (t, l) => t.copyWith(video: l.cast<VideoTrack>()));
  }

  void removeAudioClip(String clipId, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.audio);
    if (ti < 0) return;
    _saveToUndoStack();
    _removeClipFromTrack(clipId, ti,
      (t) => t.audio,
      (t, l) => t.copyWith(audio: l.cast<AudioTrack>()));
  }

  void removeOverlayClip(String clipId, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.overlays);
    if (ti < 0) return;
    _saveToUndoStack();
    _removeClipFromTrack(clipId, ti,
      (t) => t.overlays,
      (t, l) => t.copyWith(overlays: l.cast<OverlayTrack>()));
  }

  void removeSubtitleClip(String clipId, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.subtitles);
    if (ti < 0) return;
    _saveToUndoStack();
    _removeClipFromTrack(clipId, ti,
      (t) => t.subtitles,
      (t, l) => t.copyWith(subtitles: l.cast<SubtitleTrack>()));
  }

  /// إزالة أي كليب بناءً على معرفه ونوعه
  void removeClip(String clipId, String clipType) {
    switch (clipType) {
      case 'video':
        removeVideoClip(clipId);
        break;
      case 'audio':
        removeAudioClip(clipId);
        break;
      case 'overlay':
        removeOverlayClip(clipId);
        break;
      case 'subtitle':
        removeSubtitleClip(clipId);
        break;
      case 'text':
        removeTextClip(clipId);
        break;
    }
  }

  void _updateClipInTrack<T>(String clipId, int trackIndex,
      List<dynamic> Function(Tracks) getTracks,
      Tracks Function(Tracks, List<dynamic>) setTracks,
      dynamic Function(dynamic) updateFn) {
    final tracks = getTracks(state.timeline.tracks);
    if (trackIndex >= tracks.length) return;
    final targetTrack = tracks[trackIndex];
    final updatedClips = targetTrack.clips.map((clip) {
      if (clip.id == clipId) return updateFn(clip);
      return clip;
    }).toList();
    final copy = List<dynamic>.from(tracks);
    copy[trackIndex] = targetTrack.copyWith(clips: updatedClips.cast<T>());
    state = state.copyWith(
      timeline: state.timeline.copyWith(tracks: setTracks(state.timeline.tracks, copy)),
    );
  }

  void updateVideoClip(String clipId, VideoClip Function(VideoClip) updateFn, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.video);
    if (ti < 0) return;
    _saveToUndoStack();
    _updateClipInTrack<VideoClip>(clipId, ti,
      (t) => t.video,
      (t, l) => t.copyWith(video: l.cast<VideoTrack>()),
      (c) => updateFn(c as VideoClip));
  }

  void updateSubtitleClip(String clipId, SubtitleClip Function(SubtitleClip) updateFn, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.subtitles);
    if (ti < 0) return;
    _saveToUndoStack();
    _updateClipInTrack<SubtitleClip>(clipId, ti,
      (t) => t.subtitles,
      (t, l) => t.copyWith(subtitles: l.cast<SubtitleTrack>()),
      (c) => updateFn(c as SubtitleClip));
  }

  void updateAudioClip(String clipId, AudioClip Function(AudioClip) updateFn, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.audio);
    if (ti < 0) return;
    _saveToUndoStack();
    _updateClipInTrack<AudioClip>(clipId, ti,
      (t) => t.audio,
      (t, l) => t.copyWith(audio: l.cast<AudioTrack>()),
      (c) => updateFn(c as AudioClip));
  }

  void updateOverlayClip(String clipId, OverlayClip Function(OverlayClip) updateFn, {int? trackIndex}) {
    final ti = trackIndex ?? _locateClipTrack(clipId, (t) => t.overlays);
    if (ti < 0) return;
    _saveToUndoStack();
    _updateClipInTrack<OverlayClip>(clipId, ti,
      (t) => t.overlays,
      (t, l) => t.copyWith(overlays: l.cast<OverlayTrack>()),
      (c) => updateFn(c as OverlayClip));
  }

  /// مسح كافة الكليبات الحالية وتعيين كليبات جديدة (تستدعى عند التقطيع التلقائي أو استيراد كليبات جديدة)
  void setClips(List<VideoClip> newClips) {
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final videoTracks = List<VideoTrack>.from(currentTracks.video);

    if (videoTracks.isEmpty) {
      videoTracks.add(VideoTrack(id: 'v_main', name: 'Video 1', index: 0, clips: []));
    }

    videoTracks[0] = videoTracks[0].copyWith(clips: newClips);

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(video: videoTracks),
      ),
    );
  }

  /// تحريك كليب فيديو إلى موقع جديد
  /// حرّك كليب فيديو إلى موضع جديد.
  ///
  /// أثناء السحب تكون الحركة حرة (يُسمح بالتداخل مؤقتًا حتى يتبع الكليب
  /// الإصبع فعليًا) — التصادمات تُحل لاحقًا عبر [resolveVideoOverlaps]
  /// عند رفع اليد. [trackIndex] يُستنتج تلقائيًا إذا لم يُمرَّر.
  void moveVideoClip(String clipId, double newStart, {int? trackIndex}) {
    final currentTracks = state.timeline.tracks;
    final videoTracks = List<VideoTrack>.from(currentTracks.video);
    final int ti = trackIndex ??
        videoTracks.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (ti < 0 || ti >= videoTracks.length) return;

    final targetTrack = videoTracks[ti];
    final clips = targetTrack.clips;
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    _saveToUndoStack();
    final clip = clips[index];
    final dur = clip.endTimeInTimeline - clip.startTimeInTimeline;

    final double clampedStart = newStart < 0.0 ? 0.0 : newStart;

    final updatedClips = clips.map((c) {
      if (c.id == clipId) {
        return c.copyWith(
          startTimeInTimeline: clampedStart,
          endTimeInTimeline: clampedStart + dur,
        );
      }
      return c;
    }).toList();

    videoTracks[ti] = targetTrack.copyWith(clips: updatedClips);
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(video: videoTracks),
      ),
    );
  }

  /// تغيير طول كليب فيديو (من الحافة اليمنى)
  void resizeVideoClip(String clipId, double newEnd, {int? trackIndex}) {
    trackIndex ??=
        state.timeline.tracks.video.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final videoTracks = List<VideoTrack>.from(currentTracks.video);

    if (trackIndex < videoTracks.length) {
      final targetTrack = videoTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double rightLimit = double.infinity;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.startTimeInTimeline > clip.startTimeInTimeline && c.startTimeInTimeline < rightLimit) {
          rightLimit = c.startTimeInTimeline;
        }
      }
      
      double targetEnd = newEnd.clamp(clip.startTimeInTimeline + 0.1, rightLimit);
      
      final double deltaTimeline = targetEnd - clip.endTimeInTimeline;
      final double deltaSource = deltaTimeline * clip.speed;
      double targetTrimEnd = clip.sourceTrimEnd + deltaSource;
      
      final double maxAllowedTrimEnd = clip.sourceDuration > 0.0 ? clip.sourceDuration : double.infinity;
      targetTrimEnd = targetTrimEnd.clamp(clip.sourceTrimStart + 0.1, maxAllowedTrimEnd);
      
      final double finalEnd = clip.startTimeInTimeline + (targetTrimEnd - clip.sourceTrimStart) / clip.speed;
      
      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            endTimeInTimeline: finalEnd,
            sourceTrimEnd: targetTrimEnd,
          );
        }
        return c;
      }).toList();

      videoTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(video: videoTracks),
        ),
      );
    }
  }

  /// Re-probes a video clip's source file and repairs a stale [sourceDuration].
  /// Import-time probes can record a wrong (usually too short) duration — e.g.
  /// the file was still downloading — which then caps right-edge extension.
  /// Only ever GROWS the cap; returns true when the stored duration changed.
  Future<bool> refreshVideoClipSourceDuration(
    String clipId,
    Future<double?> Function(String path) probeDuration,
  ) async {
    int trackIndex = -1;
    int clipIndex = -1;
    final videoTracks = state.timeline.tracks.video;
    for (int i = 0; i < videoTracks.length && clipIndex == -1; i++) {
      clipIndex = videoTracks[i].clips.indexWhere((c) => c.id == clipId);
      if (clipIndex != -1) trackIndex = i;
    }
    if (trackIndex == -1) return false;
    final clip = videoTracks[trackIndex].clips[clipIndex];
    if (clip.sourcePath.isEmpty) return false;
    double? probed;
    try {
      probed = await probeDuration(clip.sourcePath);
    } catch (_) {
      return false;
    }
    if (probed == null || probed <= clip.sourceDuration + 0.05) return false;
    _saveToUndoStack();
    final tracks = List<VideoTrack>.from(state.timeline.tracks.video);
    final clips = List<VideoClip>.from(tracks[trackIndex].clips);
    final idx = clips.indexWhere((c) => c.id == clipId);
    if (idx == -1) return false;
    clips[idx] = clips[idx].copyWith(sourceDuration: probed);
    tracks[trackIndex] = tracks[trackIndex].copyWith(clips: clips);
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: state.timeline.tracks.copyWith(video: tracks),
      ),
    );
    return true;
  }

  /// تحريك كليب صوتي
  /// حرّك كليب صوتي — راجع [moveVideoClip] لسلوك السحب الحر.
  void moveAudioClip(String clipId, double newStart, {int? trackIndex}) {
    final currentTracks = state.timeline.tracks;
    final audioTracks = List<AudioTrack>.from(currentTracks.audio);
    final int ti = trackIndex ??
        audioTracks.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (ti < 0 || ti >= audioTracks.length) return;

    final targetTrack = audioTracks[ti];
    final clips = targetTrack.clips;
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    _saveToUndoStack();
    final clip = clips[index];
    final dur = clip.endTimeInTimeline - clip.startTimeInTimeline;
    final double clampedStart = newStart < 0.0 ? 0.0 : newStart;

    final updatedClips = clips.map((c) {
      if (c.id == clipId) {
        return c.copyWith(
          startTimeInTimeline: clampedStart,
          endTimeInTimeline: clampedStart + dur,
        );
      }
      return c;
    }).toList();

    audioTracks[ti] = targetTrack.copyWith(clips: updatedClips);
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(audio: audioTracks),
      ),
    );
  }

  /// تغيير طول كليب صوتي
  void resizeAudioClip(String clipId, double newEnd, {int? trackIndex}) {
    trackIndex ??=
        state.timeline.tracks.audio.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final audioTracks = List<AudioTrack>.from(currentTracks.audio);
    if (trackIndex < audioTracks.length) {
      final targetTrack = audioTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double rightLimit = double.infinity;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.startTimeInTimeline > clip.startTimeInTimeline && c.startTimeInTimeline < rightLimit) {
          rightLimit = c.startTimeInTimeline;
        }
      }
      
      double targetEnd = newEnd.clamp(clip.startTimeInTimeline + 0.1, rightLimit);
      
      final double deltaTimeline = targetEnd - clip.endTimeInTimeline;
      double targetTrimEnd = clip.sourceTrimEnd + deltaTimeline;
      
      final double maxAllowedTrimEnd = clip.sourceDuration > 0.0 ? clip.sourceDuration : double.infinity;
      targetTrimEnd = targetTrimEnd.clamp(clip.sourceTrimStart + 0.1, maxAllowedTrimEnd);
      
      final double finalEnd = clip.startTimeInTimeline + (targetTrimEnd - clip.sourceTrimStart);
      
      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            endTimeInTimeline: finalEnd,
            sourceTrimEnd: targetTrimEnd,
          );
        }
        return c;
      }).toList();
      audioTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(audio: audioTracks),
        ),
      );
    }
  }

  /// تغيير طول كليب فيديو من الحافة اليسرى (Trim Start)
  void resizeVideoClipLeft(String clipId, double newStart, {int? trackIndex}) {
    trackIndex ??=
        state.timeline.tracks.video.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final videoTracks = List<VideoTrack>.from(currentTracks.video);

    if (trackIndex < videoTracks.length) {
      final targetTrack = videoTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double leftLimit = 0.0;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.endTimeInTimeline < clip.endTimeInTimeline && c.endTimeInTimeline > leftLimit) {
          leftLimit = c.endTimeInTimeline;
        }
      }
      
      double targetStart = newStart.clamp(leftLimit, clip.endTimeInTimeline - 0.1);
      
      final double deltaTimeline = targetStart - clip.startTimeInTimeline;
      final double deltaSource = deltaTimeline * clip.speed;
      double targetTrimStart = clip.sourceTrimStart + deltaSource;
      
      targetTrimStart = targetTrimStart.clamp(0.0, clip.sourceTrimEnd - 0.1);
      
      final double finalStart = clip.endTimeInTimeline - (clip.sourceTrimEnd - targetTrimStart) / clip.speed;

      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            startTimeInTimeline: finalStart,
            sourceTrimStart: targetTrimStart,
          );
        }
        return c;
      }).toList();

      videoTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(video: videoTracks),
        ),
      );
    }
  }

  /// تغيير طول كليب صوتي من الحافة اليسرى (Trim Start)
  void resizeAudioClipLeft(String clipId, double newStart, {int? trackIndex}) {
    trackIndex ??=
        state.timeline.tracks.audio.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final audioTracks = List<AudioTrack>.from(currentTracks.audio);

    if (trackIndex < audioTracks.length) {
      final targetTrack = audioTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double leftLimit = 0.0;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.endTimeInTimeline < clip.endTimeInTimeline && c.endTimeInTimeline > leftLimit) {
          leftLimit = c.endTimeInTimeline;
        }
      }
      
      double targetStart = newStart.clamp(leftLimit, clip.endTimeInTimeline - 0.1);
      
      final double deltaTimeline = targetStart - clip.startTimeInTimeline;
      double targetTrimStart = clip.sourceTrimStart + deltaTimeline;
      
      targetTrimStart = targetTrimStart.clamp(0.0, clip.sourceTrimEnd - 0.1);
      
      final double finalStart = clip.endTimeInTimeline - (clip.sourceTrimEnd - targetTrimStart);

      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            startTimeInTimeline: finalStart,
            sourceTrimStart: targetTrimStart,
          );
        }
        return c;
      }).toList();

      audioTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(audio: audioTracks),
        ),
      );
    }
  }

  /// تحريك كليب تراكب
  /// حرّك كليب تراكب — راجع [moveVideoClip] لسلوك السحب الحر.
  void moveOverlayClip(String clipId, double newStart, {int? trackIndex}) {
    final currentTracks = state.timeline.tracks;
    final overlayTracks = List<OverlayTrack>.from(currentTracks.overlays);
    final int ti = trackIndex ??
        overlayTracks.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (ti < 0 || ti >= overlayTracks.length) return;

    final targetTrack = overlayTracks[ti];
    final clips = targetTrack.clips;
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    _saveToUndoStack();
    final clip = clips[index];
    final dur = clip.endTimeInTimeline - clip.startTimeInTimeline;
    final double clampedStart = newStart < 0.0 ? 0.0 : newStart;

    final updatedClips = clips.map((c) {
      if (c.id == clipId) {
        return c.copyWith(
          startTimeInTimeline: clampedStart,
          endTimeInTimeline: clampedStart + dur,
        );
      }
      return c;
    }).toList();

    overlayTracks[ti] = targetTrack.copyWith(clips: updatedClips);
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(overlays: overlayTracks),
      ),
    );
  }

  /// تغيير طول كليب تراكب من اليمين
  void resizeOverlayClip(String clipId, double newEnd, {int? trackIndex}) {
    trackIndex ??= state
        .timeline.tracks.overlays.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final overlayTracks = List<OverlayTrack>.from(currentTracks.overlays);
    if (trackIndex < overlayTracks.length) {
      final targetTrack = overlayTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double rightLimit = double.infinity;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.startTimeInTimeline > clip.startTimeInTimeline && c.startTimeInTimeline < rightLimit) {
          rightLimit = c.startTimeInTimeline;
        }
      }
      
      double targetEnd = newEnd.clamp(clip.startTimeInTimeline + 0.1, rightLimit);
      
      final double deltaTimeline = targetEnd - clip.endTimeInTimeline;
      double targetTrimEnd = clip.sourceTrimEnd + deltaTimeline;
      
      final double maxAllowedTrimEnd = clip.sourceDuration > 0.0 ? clip.sourceDuration : double.infinity;
      targetTrimEnd = targetTrimEnd.clamp(clip.sourceTrimStart + 0.1, maxAllowedTrimEnd);
      
      final double finalEnd = clip.startTimeInTimeline + (targetTrimEnd - clip.sourceTrimStart);
      
      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            endTimeInTimeline: finalEnd,
            sourceTrimEnd: targetTrimEnd,
          );
        }
        return c;
      }).toList();
      overlayTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(overlays: overlayTracks),
        ),
      );
    }
  }

  /// تغيير طول كليب تراكب من اليسار
  void resizeOverlayClipLeft(String clipId, double newStart, {int? trackIndex}) {
    trackIndex ??= state
        .timeline.tracks.overlays.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final overlayTracks = List<OverlayTrack>.from(currentTracks.overlays);
    if (trackIndex < overlayTracks.length) {
      final targetTrack = overlayTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double leftLimit = 0.0;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.endTimeInTimeline < clip.endTimeInTimeline && c.endTimeInTimeline > leftLimit) {
          leftLimit = c.endTimeInTimeline;
        }
      }
      
      double targetStart = newStart.clamp(leftLimit, clip.endTimeInTimeline - 0.1);
      
      final double deltaTimeline = targetStart - clip.startTimeInTimeline;
      double targetTrimStart = clip.sourceTrimStart + deltaTimeline;
      
      targetTrimStart = targetTrimStart.clamp(0.0, clip.sourceTrimEnd - 0.1);
      
      final double finalStart = clip.endTimeInTimeline - (clip.sourceTrimEnd - targetTrimStart);

      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            startTimeInTimeline: finalStart,
            sourceTrimStart: targetTrimStart,
          );
        }
        return c;
      }).toList();
      overlayTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(overlays: overlayTracks),
        ),
      );
    }
  }

  /// حرّك كليب ترجمة — راجع [moveVideoClip] لسلوك السحب الحر.
  void moveSubtitleClip(String clipId, double newStart, {int? trackIndex}) {
    final currentTracks = state.timeline.tracks;
    final subtitleTracks = List<SubtitleTrack>.from(currentTracks.subtitles);
    final int ti = trackIndex ??
        subtitleTracks.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (ti < 0 || ti >= subtitleTracks.length) return;

    final targetTrack = subtitleTracks[ti];
    final clips = targetTrack.clips;
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    _saveToUndoStack();
    final clip = clips[index];
    final dur = clip.endTime - clip.startTime;
    final double clampedStart = newStart < 0.0 ? 0.0 : newStart;

    final updatedClips = clips.map((c) {
      if (c.id == clipId) {
        return c.copyWith(
          startTime: clampedStart,
          endTime: clampedStart + dur,
        );
      }
      return c;
    }).toList();

    subtitleTracks[ti] = targetTrack.copyWith(clips: updatedClips);
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(subtitles: subtitleTracks),
      ),
    );
  }

  // ── Overlap resolution (called when a drag ends) ──────────────────────
  // Free dragging lets a clip pass over its neighbours so it tracks the
  // pointer. On release we restore the "no overlap per track" invariant with
  // magnetic semantics: the dragged clip STAYS where it was dropped and any
  // clip it collides with is pushed to the right (cascading).

  /// Fallback when the anchor is gone: keep time order, push overlaps right.
  static List<T> _pushOverlaps<T>(
    List<T> clips, {
    required double Function(T) startOf,
    required double Function(T) endOf,
    required T Function(T, double, double) withRange,
  }) {
    if (clips.length < 2) return clips;
    final order = List<int>.generate(clips.length, (i) => i)
      ..sort((a, b) => startOf(clips[a]).compareTo(startOf(clips[b])));

    final starts = List<double>.filled(clips.length, 0.0);
    final ends = List<double>.filled(clips.length, 0.0);
    double lastEnd = 0.0;
    var first = true;
    var changed = false;

    for (final i in order) {
      var s = startOf(clips[i]);
      var e = endOf(clips[i]);
      if (s < 0.0) {
        e -= s;
        s = 0.0;
      }
      if (!first && s < lastEnd) {
        e += lastEnd - s;
        s = lastEnd;
      }
      if (s != startOf(clips[i]) || e != endOf(clips[i])) changed = true;
      starts[i] = s;
      ends[i] = e;
      lastEnd = e;
      first = false;
    }

    if (!changed) return clips;
    return [
      for (var i = 0; i < clips.length; i++)
        withRange(clips[i], starts[i], ends[i]),
    ];
  }

  /// [anchorId] = the dragged clip: it keeps its dropped position; clips that
  /// ended up on top of it are pushed right (order-free — a clip dropped to
  /// the LEFT of a neighbour swaps past it, like a magnetic timeline).
  static List<T> _resolveAroundAnchor<T>(
    List<T> clips, {
    required String anchorId,
    required String Function(T) idOf,
    required double Function(T) startOf,
    required double Function(T) endOf,
    required T Function(T, double, double) withRange,
  }) {
    final ai = clips.indexWhere((c) => idOf(c) == anchorId);
    if (ai == -1) {
      return _pushOverlaps(clips,
          startOf: startOf, endOf: endOf, withRange: withRange);
    }

    var s = startOf(clips[ai]);
    var e = endOf(clips[ai]);
    if (s < 0.0) {
      e -= s;
      s = 0.0;
    }

    // Left side: clips entirely before the anchor stay put (the track was
    // clean before the drag, so they cannot overlap each other).
    // Everything else must clear the anchor's end.
    final rest = <int>[];
    final starts = List<double>.filled(clips.length, 0.0);
    final ends = List<double>.filled(clips.length, 0.0);
    starts[ai] = s;
    ends[ai] = e;
    var changed = s != startOf(clips[ai]) || e != endOf(clips[ai]);

    for (var i = 0; i < clips.length; i++) {
      if (i == ai) continue;
      if (endOf(clips[i]) <= s) {
        starts[i] = startOf(clips[i]);
        ends[i] = endOf(clips[i]);
      } else {
        rest.add(i);
      }
    }
    rest.sort((a, b) => startOf(clips[a]).compareTo(startOf(clips[b])));

    double cursor = e;
    for (final i in rest) {
      final dur = endOf(clips[i]) - startOf(clips[i]);
      var ns = startOf(clips[i]);
      if (ns < cursor) ns = cursor;
      final ne = ns + dur;
      if (ns != startOf(clips[i]) || ne != endOf(clips[i])) changed = true;
      starts[i] = ns;
      ends[i] = ne;
      cursor = ne;
    }

    if (!changed) return clips;
    return [
      for (var i = 0; i < clips.length; i++)
        withRange(clips[i], starts[i], ends[i]),
    ];
  }

  void resolveVideoOverlaps(String anchorId) {
    final currentTracks = state.timeline.tracks;
    final videoTracks = List<VideoTrack>.from(currentTracks.video);
    var changed = false;
    for (var i = 0; i < videoTracks.length; i++) {
      final clips = videoTracks[i].clips;
      final resolved = _resolveAroundAnchor<VideoClip>(
        clips,
        anchorId: anchorId,
        idOf: (c) => c.id,
        startOf: (c) => c.startTimeInTimeline,
        endOf: (c) => c.endTimeInTimeline,
        withRange: (c, s, e) =>
            c.copyWith(startTimeInTimeline: s, endTimeInTimeline: e),
      );
      if (!identical(resolved, clips)) {
        videoTracks[i] = videoTracks[i].copyWith(clips: resolved);
        changed = true;
      }
    }
    if (!changed) return;
    _saveToUndoStack(); // coalesced into the ongoing drag checkpoint
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(video: videoTracks),
      ),
    );
  }

  void resolveAudioOverlaps(String anchorId) {
    final currentTracks = state.timeline.tracks;
    final audioTracks = List<AudioTrack>.from(currentTracks.audio);
    var changed = false;
    for (var i = 0; i < audioTracks.length; i++) {
      final clips = audioTracks[i].clips;
      final resolved = _resolveAroundAnchor<AudioClip>(
        clips,
        anchorId: anchorId,
        idOf: (c) => c.id,
        startOf: (c) => c.startTimeInTimeline,
        endOf: (c) => c.endTimeInTimeline,
        withRange: (c, s, e) =>
            c.copyWith(startTimeInTimeline: s, endTimeInTimeline: e),
      );
      if (!identical(resolved, clips)) {
        audioTracks[i] = audioTracks[i].copyWith(clips: resolved);
        changed = true;
      }
    }
    if (!changed) return;
    _saveToUndoStack();
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(audio: audioTracks),
      ),
    );
  }

  void resolveOverlayOverlaps(String anchorId) {
    final currentTracks = state.timeline.tracks;
    final overlayTracks = List<OverlayTrack>.from(currentTracks.overlays);
    var changed = false;
    for (var i = 0; i < overlayTracks.length; i++) {
      final clips = overlayTracks[i].clips;
      final resolved = _resolveAroundAnchor<OverlayClip>(
        clips,
        anchorId: anchorId,
        idOf: (c) => c.id,
        startOf: (c) => c.startTimeInTimeline,
        endOf: (c) => c.endTimeInTimeline,
        withRange: (c, s, e) =>
            c.copyWith(startTimeInTimeline: s, endTimeInTimeline: e),
      );
      if (!identical(resolved, clips)) {
        overlayTracks[i] = overlayTracks[i].copyWith(clips: resolved);
        changed = true;
      }
    }
    if (!changed) return;
    _saveToUndoStack();
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(overlays: overlayTracks),
      ),
    );
  }

  void resolveSubtitleOverlaps(String anchorId) {
    final currentTracks = state.timeline.tracks;
    final subtitleTracks = List<SubtitleTrack>.from(currentTracks.subtitles);
    var changed = false;
    for (var i = 0; i < subtitleTracks.length; i++) {
      final clips = subtitleTracks[i].clips;
      final resolved = _resolveAroundAnchor<SubtitleClip>(
        clips,
        anchorId: anchorId,
        idOf: (c) => c.id,
        startOf: (c) => c.startTime,
        endOf: (c) => c.endTime,
        withRange: (c, s, e) => c.copyWith(startTime: s, endTime: e),
      );
      if (!identical(resolved, clips)) {
        subtitleTracks[i] = subtitleTracks[i].copyWith(clips: resolved);
        changed = true;
      }
    }
    if (!changed) return;
    _saveToUndoStack();
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(subtitles: subtitleTracks),
      ),
    );
  }

  void resolveTextOverlaps(String anchorId) {
    final currentTracks = state.timeline.tracks;
    final textTracks = List<TextTrack>.from(currentTracks.text);
    var changed = false;
    for (var i = 0; i < textTracks.length; i++) {
      final clips = textTracks[i].clips;
      final resolved = _resolveAroundAnchor<TextClip>(
        clips,
        anchorId: anchorId,
        idOf: (c) => c.id,
        startOf: (c) => c.startTime,
        endOf: (c) => c.endTime,
        withRange: (c, s, e) => c.copyWith(startTime: s, endTime: e),
      );
      if (!identical(resolved, clips)) {
        textTracks[i] = textTracks[i].copyWith(clips: resolved);
        changed = true;
      }
    }
    if (!changed) return;
    _saveToUndoStack();
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(text: textTracks),
      ),
    );
  }

  /// تغيير طول كليب ترجمة من اليمين
  void resizeSubtitleClip(String clipId, double newEnd, {int? trackIndex}) {
    trackIndex ??= state
        .timeline.tracks.subtitles.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final subtitleTracks = List<SubtitleTrack>.from(currentTracks.subtitles);
    if (trackIndex < subtitleTracks.length) {
      final targetTrack = subtitleTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double rightLimit = double.infinity;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.startTime > clip.startTime && c.startTime < rightLimit) {
          rightLimit = c.startTime;
        }
      }
      
      double targetEnd = newEnd.clamp(clip.startTime + 0.1, rightLimit);
      
      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            endTime: targetEnd,
          );
        }
        return c;
      }).toList();
      subtitleTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(subtitles: subtitleTracks),
        ),
      );
    }
  }

  /// تغيير طول كليب ترجمة من اليسار
  void resizeSubtitleClipLeft(String clipId, double newStart, {int? trackIndex}) {
    trackIndex ??= state
        .timeline.tracks.subtitles.indexWhere((t) => t.clips.any((c) => c.id == clipId));
    if (trackIndex < 0) return;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    final subtitleTracks = List<SubtitleTrack>.from(currentTracks.subtitles);
    if (trackIndex < subtitleTracks.length) {
      final targetTrack = subtitleTracks[trackIndex];
      final clips = targetTrack.clips;
      
      final index = clips.indexWhere((c) => c.id == clipId);
      if (index == -1) return;
      final clip = clips[index];
      
      double leftLimit = 0.0;
      for (var c in clips) {
        if (c.id == clipId) continue;
        if (c.endTime < clip.endTime && c.endTime > leftLimit) {
          leftLimit = c.endTime;
        }
      }
      
      double targetStart = newStart.clamp(leftLimit, clip.endTime - 0.1);
      
      final updatedClips = targetTrack.clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(
            startTime: targetStart,
          );
        }
        return c;
      }).toList();
      subtitleTracks[trackIndex] = targetTrack.copyWith(clips: updatedClips);
      state = state.copyWith(
        timeline: state.timeline.copyWith(
          tracks: currentTracks.copyWith(subtitles: subtitleTracks),
        ),
      );
    }
  }

  /// هل يوجد كليب (فيديو/صوت/ترجمة) يتقاطع مع المؤشر وقابل للقص؟
  bool canSplitAtPlayhead(double timeSec) {
    final tracks = state.timeline.tracks;
    for (final track in tracks.video) {
      for (final clip in track.clips) {
        if (timeSec > clip.startTimeInTimeline &&
            timeSec < clip.endTimeInTimeline) {
          return true;
        }
      }
    }
    for (final track in tracks.audio) {
      for (final clip in track.clips) {
        if (timeSec > clip.startTimeInTimeline &&
            timeSec < clip.endTimeInTimeline) {
          return true;
        }
      }
    }
    for (final track in tracks.subtitles) {
      for (final clip in track.clips) {
        if (timeSec > clip.startTime && timeSec < clip.endTime) return true;
      }
    }
    for (final track in tracks.overlays) {
      for (final clip in track.clips) {
        if (timeSec > clip.startTimeInTimeline &&
            timeSec < clip.endTimeInTimeline) {
          return true;
        }
      }
    }
    for (final track in tracks.text) {
      for (final clip in track.clips) {
        if (timeSec > clip.startTime && timeSec < clip.endTime) return true;
      }
    }
    return false;
  }

  /// تقسيم كليبات الفيديو، الصوت، أو الترجمات التي تتقاطع مع مؤشر القراءة.
  /// يُرجع true فقط عند حدوث قص فعلي — لا يلمس الـ Undo/Redo عند الفشل.
  bool splitClipAtPlayhead(double timeSec) {
    if (!canSplitAtPlayhead(timeSec)) return false;
    _saveToUndoStack();
    final currentTracks = state.timeline.tracks;
    
    // 1. تقسيم كليب الفيديو
    final videoTracks = List<VideoTrack>.from(currentTracks.video);
    bool didSplit = false;
    for (int i = 0; i < videoTracks.length; i++) {
      final track = videoTracks[i];
      final clips = List<VideoClip>.from(track.clips);
      for (int j = 0; j < clips.length; j++) {
        final clip = clips[j];
        if (timeSec > clip.startTimeInTimeline && timeSec < clip.endTimeInTimeline) {
          final double splitOffset = timeSec - clip.startTimeInTimeline;
          final double sourceSplitOffset = splitOffset * clip.speed;
          final originalEnd = clip.endTimeInTimeline;
          final originalTrimEnd = clip.sourceTrimEnd;
          
          final clip1 = clip.copyWith(
            endTimeInTimeline: timeSec,
            sourceTrimEnd: clip.sourceTrimStart + sourceSplitOffset,
          );
          
          final clip2 = clip.copyWith(
            id: 'clip_v_split_${DateTime.now().millisecondsSinceEpoch}_${j + 1}',
            startTimeInTimeline: timeSec,
            endTimeInTimeline: originalEnd,
            sourceTrimStart: clip.sourceTrimStart + sourceSplitOffset,
            sourceTrimEnd: originalTrimEnd,
          );
          
          clips[j] = clip1;
          clips.insert(j + 1, clip2);
          
          videoTracks[i] = track.copyWith(clips: clips);
          didSplit = true;
        }
      }
    }

    // 2. تقسيم كليب الصوت
    final audioTracks = List<AudioTrack>.from(currentTracks.audio);
    for (int i = 0; i < audioTracks.length; i++) {
      final track = audioTracks[i];
      final clips = List<AudioClip>.from(track.clips);
      for (int j = 0; j < clips.length; j++) {
        final clip = clips[j];
        if (timeSec > clip.startTimeInTimeline && timeSec < clip.endTimeInTimeline) {
          final double splitOffset = timeSec - clip.startTimeInTimeline;
          final originalEnd = clip.endTimeInTimeline;
          final originalTrimEnd = clip.sourceTrimEnd;
          
          final clip1 = clip.copyWith(
            endTimeInTimeline: timeSec,
            sourceTrimEnd: clip.sourceTrimStart + splitOffset,
          );
          
          final clip2 = clip.copyWith(
            id: 'clip_a_split_${DateTime.now().millisecondsSinceEpoch}_${j + 1}',
            startTimeInTimeline: timeSec,
            endTimeInTimeline: originalEnd,
            sourceTrimStart: clip.sourceTrimStart + splitOffset,
            sourceTrimEnd: originalTrimEnd,
          );
          
          clips[j] = clip1;
          clips.insert(j + 1, clip2);
          
          audioTracks[i] = track.copyWith(clips: clips);
          didSplit = true;
        }
      }
    }

    // 3. تقسيم كليبات الترجمة
    final subtitleTracks = List<SubtitleTrack>.from(currentTracks.subtitles);
    for (int i = 0; i < subtitleTracks.length; i++) {
      final track = subtitleTracks[i];
      final clips = List<SubtitleClip>.from(track.clips);
      for (int j = 0; j < clips.length; j++) {
        final clip = clips[j];
        if (timeSec > clip.startTime && timeSec < clip.endTime) {
          final originalEnd = clip.endTime;
          
          final clip1 = clip.copyWith(
            endTime: timeSec,
          );
          
          final clip2 = clip.copyWith(
            id: 'sub_split_${DateTime.now().millisecondsSinceEpoch}_${j + 1}',
            startTime: timeSec,
            endTime: originalEnd,
          );
          
          clips[j] = clip1;
          clips.insert(j + 1, clip2);
          
          subtitleTracks[i] = track.copyWith(clips: clips);
          didSplit = true;
        }
      }
    }

    // 4. تقسيم كليبات التراكبات (B-roll/صور) — قص مطابق للفيديو بلا تسريع
    final overlayTracks = List<OverlayTrack>.from(currentTracks.overlays);
    for (int i = 0; i < overlayTracks.length; i++) {
      final track = overlayTracks[i];
      final clips = List<OverlayClip>.from(track.clips);
      for (int j = 0; j < clips.length; j++) {
        final clip = clips[j];
        if (timeSec > clip.startTimeInTimeline && timeSec < clip.endTimeInTimeline) {
          final double splitOffset = timeSec - clip.startTimeInTimeline;
          final originalEnd = clip.endTimeInTimeline;
          final originalTrimEnd = clip.sourceTrimEnd;
          
          final clip1 = clip.copyWith(
            endTimeInTimeline: timeSec,
            sourceTrimEnd: clip.sourceTrimStart + splitOffset,
          );
          
          final clip2 = clip.copyWith(
            id: 'ovl_split_${DateTime.now().millisecondsSinceEpoch}_${j + 1}',
            startTimeInTimeline: timeSec,
            endTimeInTimeline: originalEnd,
            sourceTrimStart: clip.sourceTrimStart + splitOffset,
            sourceTrimEnd: originalTrimEnd,
          );
          
          clips[j] = clip1;
          clips.insert(j + 1, clip2);
          
          overlayTracks[i] = track.copyWith(clips: clips);
          didSplit = true;
        }
      }
    }

    // 5. تقسيم كليبات النص
    final textTracks = List<TextTrack>.from(currentTracks.text);
    for (int i = 0; i < textTracks.length; i++) {
      final track = textTracks[i];
      final clips = List<TextClip>.from(track.clips);
      for (int j = 0; j < clips.length; j++) {
        final clip = clips[j];
        if (timeSec > clip.startTime && timeSec < clip.endTime) {
          final originalEnd = clip.endTime;
          
          final clip1 = clip.copyWith(
            endTime: timeSec,
          );
          
          final clip2 = clip.copyWith(
            id: 'txt_split_${DateTime.now().millisecondsSinceEpoch}_${j + 1}',
            startTime: timeSec,
            endTime: originalEnd,
          );
          
          clips[j] = clip1;
          clips.insert(j + 1, clip2);
          
          textTracks[i] = track.copyWith(clips: clips);
          didSplit = true;
        }
      }
    }

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: currentTracks.copyWith(
          video: videoTracks,
          audio: audioTracks,
          subtitles: subtitleTracks,
          overlays: overlayTracks,
          text: textTracks,
        ),
      ),
    );
    return didSplit;
  }

  /// تجميع الكليبات المحددة في تسلسل متداخل
  void nestSelectedClips(Set<String> clipIds) {
    if (clipIds.isEmpty) return;
    _saveToUndoStack();
    final s = state.timeline;

    final videoTracks = List<VideoTrack>.from(s.tracks.video);
    final audioTracks = List<AudioTrack>.from(s.tracks.audio);
    final overlayTracks = List<OverlayTrack>.from(s.tracks.overlays);
    final subtitleTracks = List<SubtitleTrack>.from(s.tracks.subtitles);
    final textTracks = List<TextTrack>.from(s.tracks.text);

    final nestedVideo = <VideoClip>[];
    final nestedAudio = <AudioClip>[];
    final nestedOverlay = <OverlayClip>[];
    final nestedSub = <SubtitleClip>[];
    final nestedText = <TextClip>[];

    for (int i = 0; i < videoTracks.length; i++) {
      final kept = <VideoClip>[];
      for (final c in videoTracks[i].clips) {
        if (clipIds.contains(c.id)) { nestedVideo.add(c); } else { kept.add(c); }
      }
      videoTracks[i] = videoTracks[i].copyWith(clips: kept);
    }
    for (int i = 0; i < audioTracks.length; i++) {
      final kept = <AudioClip>[];
      for (final c in audioTracks[i].clips) {
        if (clipIds.contains(c.id)) { nestedAudio.add(c); } else { kept.add(c); }
      }
      audioTracks[i] = audioTracks[i].copyWith(clips: kept);
    }
    for (int i = 0; i < overlayTracks.length; i++) {
      final kept = <OverlayClip>[];
      for (final c in overlayTracks[i].clips) {
        if (clipIds.contains(c.id)) { nestedOverlay.add(c); } else { kept.add(c); }
      }
      overlayTracks[i] = overlayTracks[i].copyWith(clips: kept);
    }
    for (int i = 0; i < subtitleTracks.length; i++) {
      final kept = <SubtitleClip>[];
      for (final c in subtitleTracks[i].clips) {
        if (clipIds.contains(c.id)) { nestedSub.add(c); } else { kept.add(c); }
      }
      subtitleTracks[i] = subtitleTracks[i].copyWith(clips: kept);
    }
    for (int i = 0; i < textTracks.length; i++) {
      final kept = <TextClip>[];
      for (final c in textTracks[i].clips) {
        if (clipIds.contains(c.id)) { nestedText.add(c); } else { kept.add(c); }
      }
      textTracks[i] = textTracks[i].copyWith(clips: kept);
    }

    if (nestedVideo.isEmpty && nestedAudio.isEmpty && nestedOverlay.isEmpty && nestedSub.isEmpty && nestedText.isEmpty) return;

    final double minStart = _findMinStart(nestedVideo, nestedAudio, nestedOverlay, nestedSub, nestedText);
    final double maxEnd = _findMaxEnd(nestedVideo, nestedAudio, nestedOverlay, nestedSub, nestedText);
    final double duration = maxEnd - minStart;

    final nestedTracks = Tracks(
      video: [VideoTrack(id: 'nv_main', name: 'Nested Video 1', index: 0, clips: nestedVideo)],
      audio: [AudioTrack(id: 'na_main', name: 'Nested Audio 1', index: 0, clips: nestedAudio)],
      subtitles: [SubtitleTrack(id: 'ns_main', clips: nestedSub)],
      overlays: [OverlayTrack(id: 'no_main', clips: nestedOverlay)],
      text: [TextTrack(id: 'nt_main', clips: nestedText)],
    );

    final nestedSeq = NestedSequence(
      id: 'nest_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Nested Sequence ${s.nestedSequences.length + 1}',
      tracks: nestedTracks,
      settings: s.settings,
      duration: duration > 0 ? duration : 5.0,
      startTimeInTimeline: minStart,
    );

    state = state.copyWith(
      timeline: s.copyWith(
        tracks: s.tracks.copyWith(
          video: videoTracks,
          audio: audioTracks,
          overlays: overlayTracks,
          subtitles: subtitleTracks,
          text: textTracks,
          nestedSequenceIds: [...s.tracks.nestedSequenceIds, nestedSeq.id],
        ),
        nestedSequences: [...s.nestedSequences, nestedSeq],
      ),
    );
  }

  double _findMinStart(List<VideoClip> v, List<AudioClip> a, List<OverlayClip> o, List<SubtitleClip> s, List<TextClip> t) {
    double min = double.infinity;
    for (final c in v) { if (c.startTimeInTimeline < min) min = c.startTimeInTimeline; }
    for (final c in a) { if (c.startTimeInTimeline < min) min = c.startTimeInTimeline; }
    for (final c in o) { if (c.startTimeInTimeline < min) min = c.startTimeInTimeline; }
    for (final c in s) { if (c.startTime < min) min = c.startTime; }
    for (final c in t) { if (c.startTime < min) min = c.startTime; }
    return min == double.infinity ? 0.0 : min;
  }

  double _findMaxEnd(List<VideoClip> v, List<AudioClip> a, List<OverlayClip> o, List<SubtitleClip> s, List<TextClip> t) {
    double max = 0.0;
    for (final c in v) { if (c.endTimeInTimeline > max) max = c.endTimeInTimeline; }
    for (final c in a) { if (c.endTimeInTimeline > max) max = c.endTimeInTimeline; }
    for (final c in o) { if (c.endTimeInTimeline > max) max = c.endTimeInTimeline; }
    for (final c in s) { if (c.endTime > max) max = c.endTime; }
    for (final c in t) { if (c.endTime > max) max = c.endTime; }
    return max;
  }

  /// الحصول على المدة الإجمالية للتايملاين بناءً على آخر كليب
  double get totalDuration {
    double duration = 0.0;
    for (var track in state.timeline.tracks.video) {
      for (var clip in track.clips) {
        if (clip.endTimeInTimeline > duration) duration = clip.endTimeInTimeline;
      }
    }
    for (var track in state.timeline.tracks.audio) {
      for (var clip in track.clips) {
        if (clip.endTimeInTimeline > duration) duration = clip.endTimeInTimeline;
      }
    }
    for (var track in state.timeline.tracks.overlays) {
      for (var clip in track.clips) {
        if (clip.endTimeInTimeline > duration) duration = clip.endTimeInTimeline;
      }
    }
    for (var track in state.timeline.tracks.subtitles) {
      for (var clip in track.clips) {
        if (clip.endTime > duration) duration = clip.endTime;
      }
    }
    return duration > 0 ? duration : 10.0; // افتراض 10 ثوانٍ كحد أدنى
  }

  /// تعيين كليب متعدد الكاميرات (Multicam)
  void setMulticamClip(MulticamClip clip) {
    _saveToUndoStack();
    state = state.copyWith(
      timeline: state.timeline.copyWith(activeMulticam: clip),
    );
  }

  /// إضافة تبديل زاوية في MulticamClip
  void addAngleSwitch(AngleSwitch sw) {
    _saveToUndoStack();
    final mc = state.timeline.activeMulticam;
    if (mc == null) return;
    final updatedSwitches = List<AngleSwitch>.from(mc.switches)
      ..add(sw)
      ..sort((a, b) => a.time.compareTo(b.time));
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        activeMulticam: mc.copyWith(switches: updatedSwitches),
      ),
    );
  }

  /// إزالة تبديل زاوية
  void removeAngleSwitch(double time, String angleId) {
    _saveToUndoStack();
    final mc = state.timeline.activeMulticam;
    if (mc == null) return;
    final updatedSwitches = mc.switches
        .where((s) => !(s.time == time && s.angleId == angleId))
        .toList();
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        activeMulticam: mc.copyWith(switches: updatedSwitches),
      ),
    );
  }

  /// مسح MulticamClip
  void clearMulticam() {
    _saveToUndoStack();
    state = state.copyWith(
      timeline: state.timeline.copyWith(activeMulticam: null),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Clipboard + selection helpers (used by Edit menu in HeaderWidget)
  // ─────────────────────────────────────────────────────────────────────

  /// Internal clipboard for cut/copy/paste operations.
  List<Map<String, dynamic>> _clipboard = [];

  /// Cut: remove selected clips from timeline and stash them in the clipboard.
  void cutSelectedClips({Set<String>? selectedIds}) {
    final ids = selectedIds ?? state.selectedClipIds;
    if (ids.isEmpty) return;
    _saveToUndoStack();
    _clipboard = _collectClipsByIds(ids).map((c) => c.toJson() as Map<String, dynamic>).toList();
    _removeClipsByIds(ids);
    clearSelection();
  }

  /// Copy: snapshot selected clips into the clipboard without removing them.
  void copySelectedClips({Set<String>? selectedIds}) {
    final ids = selectedIds ?? state.selectedClipIds;
    if (ids.isEmpty) return;
    _clipboard = _collectClipsByIds(ids).map((c) => c.toJson() as Map<String, dynamic>).toList();
  }

  /// Paste: insert clipboard entries at the playhead.
  void pasteClips() {
    if (_clipboard.isEmpty) return;
    _saveToUndoStack();
    final playhead = state.timeline.playheadSec;
    final s = state.timeline;

    final videoTracks = List<VideoTrack>.from(s.tracks.video);
    final audioTracks = List<AudioTrack>.from(s.tracks.audio);
    final overlayTracks = List<OverlayTrack>.from(s.tracks.overlays);
    final subtitleTracks = List<SubtitleTrack>.from(s.tracks.subtitles);
    final textTracks = List<TextTrack>.from(s.tracks.text);

    for (final entry in _clipboard) {
      final type = entry['type'] as String?;
      final newId = '${type}_${DateTime.now().millisecondsSinceEpoch}';
      final reidentified = Map<String, dynamic>.from(entry)..['id'] = newId;
      switch (type) {
        case 'video':
          if (videoTracks.isNotEmpty) {
            final clip = VideoClip.fromJson(reidentified)
                .copyWith(startTimeInTimeline: playhead);
            videoTracks[0] = videoTracks[0].copyWith(clips: [...videoTracks[0].clips, clip]);
          }
          break;
        case 'audio':
          if (audioTracks.isNotEmpty) {
            final clip = AudioClip.fromJson(reidentified)
                .copyWith(startTimeInTimeline: playhead);
            audioTracks[0] = audioTracks[0].copyWith(clips: [...audioTracks[0].clips, clip]);
          }
          break;
        case 'overlay':
          if (overlayTracks.isNotEmpty) {
            final clip = OverlayClip.fromJson(reidentified)
                .copyWith(startTimeInTimeline: playhead);
            overlayTracks[0] = overlayTracks[0].copyWith(clips: [...overlayTracks[0].clips, clip]);
          }
          break;
        case 'subtitle':
          if (subtitleTracks.isNotEmpty) {
            final clip = SubtitleClip.fromJson(reidentified)
                .copyWith(startTime: playhead);
            subtitleTracks[0] = subtitleTracks[0].copyWith(clips: [...subtitleTracks[0].clips, clip]);
          }
          break;
        case 'text':
          if (textTracks.isNotEmpty) {
            final clip = TextClip.fromJson(reidentified)
                .copyWith(startTime: playhead);
            textTracks[0] = textTracks[0].copyWith(clips: [...textTracks[0].clips, clip]);
          }
          break;
      }
    }

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: s.tracks.copyWith(
          video: videoTracks,
          audio: audioTracks,
          overlays: overlayTracks,
          subtitles: subtitleTracks,
          text: textTracks,
        ),
      ),
    );
  }

  /// Select all clips across all tracks.
  void selectAllClips() {
    final ids = <String>{};
    final s = state.timeline;
    for (final t in s.tracks.video) {
      for (final c in t.clips) {
        ids.add(c.id);
      }
    }
    for (final t in s.tracks.audio) {
      for (final c in t.clips) {
        ids.add(c.id);
      }
    }
    for (final t in s.tracks.overlays) {
      for (final c in t.clips) {
        ids.add(c.id);
      }
    }
    for (final t in s.tracks.subtitles) {
      for (final c in t.clips) {
        ids.add(c.id);
      }
    }
    for (final t in s.tracks.text) {
      for (final c in t.clips) {
        ids.add(c.id);
      }
    }
    state = state.copyWith(selectedClipIds: ids);
  }

  /// Delete all clips identified by [selectedIds].
  void deleteSelectedClips({Set<String>? selectedIds}) {
    final ids = selectedIds ?? state.selectedClipIds;
    if (ids.isEmpty) return;
    _saveToUndoStack();
    _removeClipsByIds(ids);
    clearSelection();
  }

  /// Apply [speed] to every clip in [selectedIds].
  void setSelectedClipsSpeed(double speed, {Set<String>? selectedIds}) {
    final ids = selectedIds ?? state.selectedClipIds;
    if (ids.isEmpty) return;
    _saveToUndoStack();
    final s = state.timeline;
    final videoTracks = List<VideoTrack>.from(s.tracks.video);
    for (int i = 0; i < videoTracks.length; i++) {
      final clips = List<VideoClip>.from(videoTracks[i].clips);
      bool changed = false;
      for (int j = 0; j < clips.length; j++) {
        if (ids.contains(clips[j].id)) {
          clips[j] = clips[j].copyWith(speed: speed);
          changed = true;
        }
      }
      if (changed) videoTracks[i] = videoTracks[i].copyWith(clips: clips);
    }
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: s.tracks.copyWith(video: videoTracks),
      ),
    );
  }

  /// Select a single clip, optionally clearing other selections first.
  void selectClip(String id, {bool exclusive = true}) {
    final current = exclusive ? <String>{} : Set<String>.from(state.selectedClipIds);
    current.add(id);
    state = state.copyWith(selectedClipIds: current);
  }

  /// Clear the active selection.
  void clearSelection() {
    state = state.copyWith(selectedClipIds: const {});
  }

  /// Nest the currently selected clips.
  void nestCurrentSelection() {
    if (state.selectedClipIds.isEmpty) return;
    nestSelectedClips(state.selectedClipIds);
    clearSelection();
  }

  /// Nest selected clips into a new NestedSequence.
  void nestSelectedClipsByIds(Set<String> clipIds) => nestSelectedClips(clipIds);

  /// Append a new empty video track at the end of the video track list.
  void addVideoTrack() {
    _saveToUndoStack();
    final s = state.timeline;
    final videoTracks = List<VideoTrack>.from(s.tracks.video);
    final nextIdx = videoTracks.length;
    videoTracks.add(VideoTrack(
      id: 'v${nextIdx + 1}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'V${nextIdx + 1}',
      index: nextIdx,
      clips: const [],
    ));
    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: s.tracks.copyWith(video: videoTracks),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Internal helpers for clipboard / selection operations
  // ─────────────────────────────────────────────────────────────────────

  List<dynamic> _collectClipsByIds(Set<String> ids) {
    final out = <dynamic>[];
    final s = state.timeline;
    for (final t in s.tracks.video) {
      for (final c in t.clips) {
        if (ids.contains(c.id)) out.add(_TaggedClip('video', c));
      }
    }
    for (final t in s.tracks.audio) {
      for (final c in t.clips) {
        if (ids.contains(c.id)) out.add(_TaggedClip('audio', c));
      }
    }
    for (final t in s.tracks.overlays) {
      for (final c in t.clips) {
        if (ids.contains(c.id)) out.add(_TaggedClip('overlay', c));
      }
    }
    for (final t in s.tracks.subtitles) {
      for (final c in t.clips) {
        if (ids.contains(c.id)) out.add(_TaggedClip('subtitle', c));
      }
    }
    for (final t in s.tracks.text) {
      for (final c in t.clips) {
        if (ids.contains(c.id)) out.add(_TaggedClip('text', c));
      }
    }
    return out;
  }

  void _removeClipsByIds(Set<String> ids) {
    final s = state.timeline;
    final videoTracks = List<VideoTrack>.from(s.tracks.video);
    final audioTracks = List<AudioTrack>.from(s.tracks.audio);
    final overlayTracks = List<OverlayTrack>.from(s.tracks.overlays);
    final subtitleTracks = List<SubtitleTrack>.from(s.tracks.subtitles);
    final textTracks = List<TextTrack>.from(s.tracks.text);

    for (int i = 0; i < videoTracks.length; i++) {
      videoTracks[i] = videoTracks[i].copyWith(
        clips: videoTracks[i].clips.where((c) => !ids.contains(c.id)).toList(),
      );
    }
    for (int i = 0; i < audioTracks.length; i++) {
      audioTracks[i] = audioTracks[i].copyWith(
        clips: audioTracks[i].clips.where((c) => !ids.contains(c.id)).toList(),
      );
    }
    for (int i = 0; i < overlayTracks.length; i++) {
      overlayTracks[i] = overlayTracks[i].copyWith(
        clips: overlayTracks[i].clips.where((c) => !ids.contains(c.id)).toList(),
      );
    }
    for (int i = 0; i < subtitleTracks.length; i++) {
      subtitleTracks[i] = subtitleTracks[i].copyWith(
        clips: subtitleTracks[i].clips.where((c) => !ids.contains(c.id)).toList(),
      );
    }
    for (int i = 0; i < textTracks.length; i++) {
      textTracks[i] = textTracks[i].copyWith(
        clips: textTracks[i].clips.where((c) => !ids.contains(c.id)).toList(),
      );
    }

    state = state.copyWith(
      timeline: state.timeline.copyWith(
        tracks: s.tracks.copyWith(
          video: videoTracks,
          audio: audioTracks,
          overlays: overlayTracks,
          subtitles: subtitleTracks,
          text: textTracks,
        ),
      ),
    );
  }
}

/// Internal helper class used by the clipboard to tag clip JSON with its type.
class _TaggedClip {
  final String type;
  final dynamic clip;
  _TaggedClip(this.type, this.clip);
  Map<String, dynamic> toJson() {
    final out = Map<String, dynamic>.from(clip.toJson() as Map);
    out['type'] = type;
    return out;
  }
}

final timelineProvider = StateNotifierProvider<TimelineNotifier, TimelineStateData>((ref) {
  return TimelineNotifier();
});

/// بروفايدر لمؤشر السكوب المباشر — يتحدّث أثناء السحب بدون ما يسبب rebuild كامل
final scrubPlayheadProvider = StateProvider<double>((ref) => 0.0);
