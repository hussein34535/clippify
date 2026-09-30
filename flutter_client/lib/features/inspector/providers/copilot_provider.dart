import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../timeline/providers/timeline_provider.dart';
import '../../../core/models/timeline_models.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class CopilotStateData {
  final List<ChatMessage> messages;
  final bool isLoading;

  CopilotStateData({required this.messages, required this.isLoading});

  CopilotStateData copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
  }) {
    return CopilotStateData(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// أمر محلي يفهمه المساعد بدون باك إند (عربي/إنجليزي).
enum LocalCopilotKind { deleteClip, setSpeed, setVolume, splitAtPlayhead, undo, redo }

class LocalCopilotCommand {
  final LocalCopilotKind kind;

  /// القيمة: سرعة/صوت مطلقة، أو علامة نسبية (< 0).
  /// السرعة: ‎-1 = ×2 عن الحالية، ‎-2 = ‎÷2. الصوت: ‎-1 = ‎-0.2، ‎-2 = ‎+0.2.
  final double? value;
  const LocalCopilotCommand(this.kind, [this.value]);
}

double? _extractNumber(String text) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var norm = text;
  for (var i = 0; i < arabicDigits.length; i++) {
    norm = norm.replaceAll(arabicDigits[i], '$i');
  }
  norm = norm.replaceAll('٫', '.').replaceAll(',', '.');
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(norm);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// إسقاط علامات التشكيل العربية (U+064B–U+0655 وU+0670) — سرّع تصبح سرع
/// فلا تكسر مطابقة الكلمات. بوحدات UTF-16 (كل التشكيل في BMP).
String _stripTashkeel(String s) {
  final buf = StringBuffer();
  for (final code in s.codeUnits) {
    if ((code >= 0x064B && code <= 0x0655) || code == 0x0670) continue;
    buf.writeCharCode(code);
  }
  return buf.toString();
}

/// محلل أوامر نقي قابل للاختبار — يعيد null لما لا يفهم (يُرسَل للباك إند).
LocalCopilotCommand? parseLocalCopilotCommand(String prompt) {
  final t = prompt.trim();
  if (t.isEmpty) return null;
  final lower = _stripTashkeel(t.toLowerCase());
  if (RegExp(r'تراجع|undo').hasMatch(lower)) {
    return const LocalCopilotCommand(LocalCopilotKind.undo);
  }
  if (RegExp(r'إعادة|اعادة|تقدم|redo').hasMatch(lower)) {
    return const LocalCopilotCommand(LocalCopilotKind.redo);
  }
  if (RegExp(r'قص|split|شطر').hasMatch(lower)) {
    return const LocalCopilotCommand(LocalCopilotKind.splitAtPlayhead);
  }
  if (RegExp(r'احذف|امسح|حذف|مسح|delete|remove|شيل').hasMatch(lower)) {
    return const LocalCopilotCommand(LocalCopilotKind.deleteClip);
  }
  if (RegExp(r'سرع|speed|تسريع|تبط|بطئ|بطي|أسرع|اسرع|أبطأ|ابطأ|faster|slower|slow|quick')
      .hasMatch(lower)) {
    final n = _extractNumber(t);
    if (n != null) {
      return LocalCopilotCommand(LocalCopilotKind.setSpeed, n);
    }
    // فعل عارٍ بلا رقم: مطابقة توكن كامل حتى لا يلتبس الاسم (السرعة) بالفعل.
    final words =
        lower.split(RegExp(r'[\s،,.!?؛:]+')).toSet();
    const fasterVerbs = {
      'سرع', 'اسرع', 'أسرع', 'تسريع', 'faster', 'speed', 'quicker'
    };
    const slowerVerbs = {
      'ابطأ', 'أبطأ', 'تبطئ', 'تبطي', 'بطئ', 'بطي', 'slower', 'slow'
    };
    if (words.intersection(fasterVerbs).isNotEmpty ||
        RegExp(r'speed up').hasMatch(lower)) {
      return const LocalCopilotCommand(LocalCopilotKind.setSpeed, -1);
    }
    if (words.intersection(slowerVerbs).isNotEmpty ||
        RegExp(r'slow down').hasMatch(lower)) {
      return const LocalCopilotCommand(LocalCopilotKind.setSpeed, -2);
    }
    return null;
  }
  if (RegExp(r'صوت|volume|اخفض|ارفع|اكتم|mute|اصمت|علي الصوت|وطي الصوت|quiet|loud')
      .hasMatch(lower)) {
    if (RegExp(r'اكتم|mute|اصمت|صامت').hasMatch(lower)) {
      return const LocalCopilotCommand(LocalCopilotKind.setVolume, 0);
    }
    final n = _extractNumber(t);
    if (n != null) {
      return LocalCopilotCommand(
          LocalCopilotKind.setVolume, n > 2 ? n / 100 : n);
    }
    if (RegExp(r'اخفض|وطي|lower|down|quieter').hasMatch(lower)) {
      return const LocalCopilotCommand(LocalCopilotKind.setVolume, -1);
    }
    if (RegExp(r'ارفع|علي|raise|up|louder').hasMatch(lower)) {
      return const LocalCopilotCommand(LocalCopilotKind.setVolume, -2);
    }
    return null;
  }
  return null;
}

class CopilotNotifier extends StateNotifier<CopilotStateData> {
  CopilotNotifier() : super(CopilotStateData(messages: [], isLoading: false));

  Future<void> sendPrompt(String prompt, WidgetRef ref) async {
    final userMessage = ChatMessage(text: prompt, isUser: true);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
    );

    // أولًا: الأوامر المحلية (أوفلاين بالكامل) — كانت كل الأوامر تذهب
    // لendpoint ميت (501) فيرد المساعد بالفشل دائمًا.
    final local = parseLocalCopilotCommand(prompt);
    if (local != null) {
      final reply = applyLocalCommand(
        local,
        ref.read(timelineProvider.notifier),
      );
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(text: reply, isUser: false)
        ],
        isLoading: false,
      );
      return;
    }

    final timelineState = ref.read(timelineProvider).timeline;
    
    // سنقوم بتمرير نصوص تجريبية أو فارغة للباك إند
    final List<Map<String, dynamic>> dummyTranscript = [];

    final apiClient = ApiClient();
    final response = await apiClient.copilotChat(
      prompt: prompt,
      transcript: dummyTranscript,
      timelineState: timelineState.toJson(),
    );

    switch (response) {
      case Success(data: final data):
        final responseMessage = data['response_message'] as String? ?? 'تمت المعالجة بنجاح.';
        final actions = data['actions'] as List<dynamic>? ?? [];

        final aiMessage = ChatMessage(text: responseMessage, isUser: false);
        state = state.copyWith(
          messages: [...state.messages, aiMessage],
          isLoading: false,
        );

        if (actions.isNotEmpty) {
          _applyTimelineActions(actions, ref);
        }
      case Failure():
        final errorMessage = ChatMessage(text: 'عذراً، فشل الاتصال بالمساعد الذكي للباك إند.', isUser: false);
        state = state.copyWith(
          messages: [...state.messages, errorMessage],
          isLoading: false,
        );
    }
  }

  /// تنفيذ أمر محلي على التايملاين — دالة خالصة من الـ ref (تُختبر مباشرة
  /// عبر TimelineNotifier) وتعيد رد المساعد بالعربية.
  String applyLocalCommand(LocalCopilotCommand cmd, TimelineNotifier notifier) {
    final timeline = notifier.state.timeline;
    switch (cmd.kind) {
      case LocalCopilotKind.undo:
        if (!notifier.canUndo) return 'لا يوجد ما يمكن التراجع عنه.';
        notifier.undo();
        return 'تم التراجع.';
      case LocalCopilotKind.redo:
        if (!notifier.canRedo) return 'لا يوجد ما يمكن إعادته.';
        notifier.redo();
        return 'تمت الإعادة.';
      case LocalCopilotKind.splitAtPlayhead:
        final done =
            notifier.splitClipAtPlayhead(timeline.playheadSec);
        return done ? 'تم القص عند المؤشر.' : 'لا يوجد مقطع تحت المؤشر.';
      case LocalCopilotKind.deleteClip:
        final target = _resolveTarget(notifier);
        if (target == null) return 'لا يوجد مقطع للحذف.';
        switch (target.$1) {
          case 'video':
            notifier.removeVideoClip(target.$2);
          case 'audio':
            notifier.removeAudioClip(target.$2);
          default:
            return 'الحذف المحلي يدعم مقاطع الفيديو والصوت فقط.';
        }
        return 'تم حذف المقطع.';
      case LocalCopilotKind.setSpeed:
      case LocalCopilotKind.setVolume:
        return _applyClipSetting(cmd, notifier);
    }
  }

  /// (النوع، المعرف) للمقطع المستهدف: المحدد أولًا ثم أول فيديو.
  (String, String)? _resolveTarget(TimelineNotifier notifier) {
    final selected = notifier.state.selectedClipIds;
    final tracks = notifier.state.timeline.tracks;
    if (selected.isNotEmpty) {
      final id = selected.first;
      for (final t in tracks.video) {
        for (final c in t.clips) {
          if (c.id == id) return ('video', id);
        }
      }
      for (final t in tracks.audio) {
        for (final c in t.clips) {
          if (c.id == id) return ('audio', id);
        }
      }
    }
    if (tracks.video.isNotEmpty && tracks.video.first.clips.isNotEmpty) {
      return ('video', tracks.video.first.clips.first.id);
    }
    if (tracks.audio.isNotEmpty && tracks.audio.first.clips.isNotEmpty) {
      return ('audio', tracks.audio.first.clips.first.id);
    }
    return null;
  }

  String _applyClipSetting(
      LocalCopilotCommand cmd, TimelineNotifier notifier) {
    final target = _resolveTarget(notifier);
    if (target == null) return 'لا يوجد مقطع للتعديل.';
    final isSpeed = cmd.kind == LocalCopilotKind.setSpeed;
    VideoClip? video;
    AudioClip? audio;
    if (target.$1 == 'video') {
      for (final t in notifier.state.timeline.tracks.video) {
        for (final c in t.clips) {
          if (c.id == target.$2) video = c;
        }
      }
    } else {
      for (final t in notifier.state.timeline.tracks.audio) {
        for (final c in t.clips) {
          if (c.id == target.$2) audio = c;
        }
      }
    }
    if (isSpeed) {
      if (video == null) return 'السرعة لمقاطع الفيديو فقط.';
      var speed = cmd.value ?? 1.0;
      if (speed == -1) speed = (video.speed * 2).clamp(0.25, 4.0);
      if (speed == -2) speed = (video.speed / 2).clamp(0.25, 4.0);
      if (speed <= 0) return 'سرعة غير صالحة.';
      notifier.updateVideoClip(video.id, (c) => c.withSpeed(speed));
      return 'تم ضبط السرعة على ${speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 2)}x.';
    }
    var volume = cmd.value ?? 1.0;
    if (video != null) {
      if (volume == -1) volume = (video.volume - 0.2).clamp(0.0, 3.0);
      if (volume == -2) volume = (video.volume + 0.2).clamp(0.0, 3.0);
      notifier.updateVideoClip(
          video.id, (c) => c.copyWith(volume: volume.clamp(0.0, 3.0)));
    } else if (audio != null) {
      if (volume == -1) volume = (audio.volume - 0.2).clamp(0.0, 3.0);
      if (volume == -2) volume = (audio.volume + 0.2).clamp(0.0, 3.0);
      notifier.updateAudioClip(
          audio.id, (c) => c.copyWith(volume: volume.clamp(0.0, 3.0)));
    } else {
      return 'لا يوجد مقطع للتعديل.';
    }
    return 'تم ضبط الصوت.';
  }

  String? _findClipType(String clipId, WidgetRef ref) {
    final tracks = ref.read(timelineProvider).timeline.tracks;
    for (final t in tracks.video) { for (final c in t.clips) { if (c.id == clipId) return 'video'; } }
    for (final t in tracks.audio) { for (final c in t.clips) { if (c.id == clipId) return 'audio'; } }
    for (final t in tracks.overlays) { for (final c in t.clips) { if (c.id == clipId) return 'overlay'; } }
    for (final t in tracks.subtitles) { for (final c in t.clips) { if (c.id == clipId) return 'subtitle'; } }
    for (final t in tracks.text) { for (final c in t.clips) { if (c.id == clipId) return 'text'; } }
    return null;
  }

  void _applyTimelineActions(List<dynamic> actions, WidgetRef ref) {
    final notifier = ref.read(timelineProvider.notifier);

    for (var act in actions) {
      final type = act['type'] as String?;
      final clipId = act['clip_id'] as String?;
      if (clipId == null) continue;
      final clipType = _findClipType(clipId, ref);

      if (type == 'delete_clip') {
        switch (clipType) {
          case 'video': notifier.removeVideoClip(clipId); break;
          case 'audio': notifier.removeAudioClip(clipId); break;
          case 'overlay': notifier.removeOverlayClip(clipId); break;
          case 'subtitle': notifier.removeSubtitleClip(clipId); break;
          case 'text': notifier.removeTextClip(clipId); break;
        }
      } else if (type == 'update_clip') {
        final fields = act['fields'] as Map<String, dynamic>?;
        if (fields == null) continue;

        if (clipType == 'video') {
          final wantSpeed = fields.containsKey('speed')
              ? (fields['speed'] as num).toDouble()
              : null;
          notifier.updateVideoClip(clipId, (clip) {
            var out = clip.copyWith(
              aiFeatures: fields.containsKey('ai_features')
                  ? AIFeatures.fromJson(fields['ai_features'] as Map<String, dynamic>) : clip.aiFeatures,
              transform: fields.containsKey('transform')
                  ? TransformState.fromJson(fields['transform'] as Map<String, dynamic>) : clip.transform,
              colorGrading: fields.containsKey('color_grading')
                  ? ColorGradingState.fromJson(fields['color_grading'] as Map<String, dynamic>) : clip.colorGrading,
              volume: fields.containsKey('volume') ? (fields['volume'] as num).toDouble() : clip.volume,
            );
            // السرعة وحدها تغيّر الطول — تمرّ عبر withSpeed لتبقى متسقة.
            if (wantSpeed != null) out = out.withSpeed(wantSpeed);
            return out;
          });
        } else if (clipType == 'audio') {
          notifier.updateAudioClip(clipId, (clip) {
            return clip.copyWith(volume: fields['volume'] != null ? (fields['volume'] as num).toDouble() : clip.volume);
          });
        } else if (clipType == 'overlay') {
          notifier.updateOverlayClip(clipId, (clip) {
            return clip.copyWith(
              transform: fields.containsKey('transform')
                  ? TransformState.fromJson(fields['transform'] as Map<String, dynamic>) : clip.transform,
              text: fields.containsKey('text') ? fields['text'] as String : clip.text,
              opacity: fields.containsKey('opacity') ? (fields['opacity'] as num).toDouble() : clip.opacity,
              colorGrading: fields.containsKey('color_grading')
                  ? ColorGradingState.fromJson(fields['color_grading'] as Map<String, dynamic>) : clip.colorGrading,
            );
          });
        } else if (clipType == 'subtitle') {
          notifier.updateSubtitleClip(clipId, (clip) {
            return clip.copyWith(text: fields['text'] as String? ?? clip.text);
          });
        }
      }
    }
  }
}

final copilotProvider = StateNotifierProvider<CopilotNotifier, CopilotStateData>((ref) {
  return CopilotNotifier();
});
