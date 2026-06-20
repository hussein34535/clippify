import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/timeline_models.dart';
import '../../features/timeline/providers/timeline_provider.dart';
import 'toast_provider.dart';

class MacroState {
  final bool isRecording;
  final List<Map<String, dynamic>> recordedActions;

  MacroState({
    this.isRecording = false,
    this.recordedActions = const [],
  });

  MacroState copyWith({
    bool? isRecording,
    List<Map<String, dynamic>>? recordedActions,
  }) {
    return MacroState(
      isRecording: isRecording ?? this.isRecording,
      recordedActions: recordedActions ?? this.recordedActions,
    );
  }
}

class MacroNotifier extends StateNotifier<MacroState> {
  MacroNotifier() : super(MacroState());

  void startRecording() {
    state = MacroState(isRecording: true, recordedActions: []);
  }

  void stopRecording() {
    state = state.copyWith(isRecording: false);
  }

  void recordAction(String name, Map<String, dynamic> args) {
    if (!state.isRecording) return;
    final action = {
      'name': name,
      'args': args,
    };
    state = state.copyWith(
      recordedActions: [...state.recordedActions, action],
    );
  }

  Future<void> playMacro(WidgetRef ref) async {
    if (state.recordedActions.isEmpty) {
      ref.read(toastProvider.notifier).info('لا توجد خطوات مسجلة لتشغيلها.');
      return;
    }

    ref.read(toastProvider.notifier).info('جاري تشغيل الماكرو المسجل (${state.recordedActions.length} خطوة)...');
    
    try {
      final timelineState = ref.read(timelineProvider).timeline;
      final response = await ApiClient().executeAIActions(
        state.recordedActions,
        timelineState.toJson(),
      );

      switch (response) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            if (data['new_state'] != null) {
              final newState = TimelineState.fromJson(data['new_state'] as Map<String, dynamic>);
              ref.read(timelineProvider.notifier).updateTimelineState(newState);
            }
            ref.read(toastProvider.notifier).success('تم تطبيق الماكرو بنجاح! 🎉');
          } else {
            ref.read(toastProvider.notifier).error('فشل تطبيق الماكرو بالخادم.');
          }
        case Failure(message: final msg):
          ref.read(toastProvider.notifier).error('خطأ أثناء تشغيل الماكرو: $msg');
      }
    } catch (e) {
      ref.read(toastProvider.notifier).error('خطأ أثناء تشغيل الماكرو: $e');
    }
  }
}

final macroProvider = StateNotifierProvider<MacroNotifier, MacroState>((ref) {
  return MacroNotifier();
});
