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

class CopilotNotifier extends StateNotifier<CopilotStateData> {
  CopilotNotifier() : super(CopilotStateData(messages: [], isLoading: false));

  Future<void> sendPrompt(String prompt, WidgetRef ref) async {
    final userMessage = ChatMessage(text: prompt, isUser: true);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
    );

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
          notifier.updateVideoClip(clipId, (clip) {
            return clip.copyWith(
              aiFeatures: fields.containsKey('ai_features')
                  ? AIFeatures.fromJson(fields['ai_features'] as Map<String, dynamic>) : clip.aiFeatures,
              transform: fields.containsKey('transform')
                  ? TransformState.fromJson(fields['transform'] as Map<String, dynamic>) : clip.transform,
              colorGrading: fields.containsKey('color_grading')
                  ? ColorGradingState.fromJson(fields['color_grading'] as Map<String, dynamic>) : clip.colorGrading,
              speed: fields.containsKey('speed') ? (fields['speed'] as num).toDouble() : clip.speed,
              volume: fields.containsKey('volume') ? (fields['volume'] as num).toDouble() : clip.volume,
            );
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
