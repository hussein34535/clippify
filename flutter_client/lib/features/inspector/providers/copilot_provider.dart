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

  /// تطبيق التعديلات المستلمة من الذكاء الاصطناعي على التايملاين
  void _applyTimelineActions(List<dynamic> actions, WidgetRef ref) {
    final timelineNotifier = ref.read(timelineProvider.notifier);

    for (var act in actions) {
      final type = act['type'] as String?;
      if (type == 'delete_clip') {
        final clipId = act['clip_id'] as String?;
        if (clipId != null) {
          timelineNotifier.removeVideoClip(clipId);
        }
      } else if (type == 'update_clip') {
        final clipId = act['clip_id'] as String?;
        final fields = act['fields'] as Map<String, dynamic>?;
        
        if (clipId != null && fields != null) {
          timelineNotifier.updateVideoClip(clipId, (clip) {
            // تحديث الحجم أو ميزات الذكاء الاصطناعي
            AIFeatures ai = clip.aiFeatures;
            TransformState trans = clip.transform;
            ColorGradingState color = clip.colorGrading;
            double speed = clip.speed;
            double volume = clip.volume;

            if (fields.containsKey('ai_features')) {
              ai = AIFeatures.fromJson(fields['ai_features'] as Map<String, dynamic>);
            }
            if (fields.containsKey('transform')) {
              trans = TransformState.fromJson(fields['transform'] as Map<String, dynamic>);
            }
            if (fields.containsKey('color_grading')) {
              color = ColorGradingState.fromJson(fields['color_grading'] as Map<String, dynamic>);
            }
            if (fields.containsKey('speed')) {
              speed = (fields['speed'] as num).toDouble();
            }
            if (fields.containsKey('volume')) {
              volume = (fields['volume'] as num).toDouble();
            }

            return clip.copyWith(
              aiFeatures: ai,
              transform: trans,
              colorGrading: color,
              speed: speed,
              volume: volume,
            );
          });
        }
      }
    }
  }
}

final copilotProvider = StateNotifierProvider<CopilotNotifier, CopilotStateData>((ref) {
  return CopilotNotifier();
});
