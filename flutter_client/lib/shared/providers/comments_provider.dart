import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimelineComment {
  final String id;
  final double timeSec;
  final String text;
  final DateTime createdAt;

  TimelineComment({
    required this.id,
    required this.timeSec,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time_sec': timeSec,
        'text': text,
        'created_at': createdAt.toIso8601String(),
      };

  factory TimelineComment.fromJson(Map<String, dynamic> json) =>
      TimelineComment(
        id: json['id'] as String? ?? 'comment_${DateTime.now().millisecondsSinceEpoch}',
        timeSec: (json['time_sec'] as num?)?.toDouble() ?? 0.0,
        text: json['text'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class CommentsNotifier extends StateNotifier<List<TimelineComment>> {
  CommentsNotifier() : super([]);

  void addComment(double timeSec, String text) {
    final comment = TimelineComment(
      id: 'comment_${DateTime.now().millisecondsSinceEpoch}',
      timeSec: timeSec,
      text: text,
      createdAt: DateTime.now(),
    );
    state = [...state, comment]..sort((a, b) => a.timeSec.compareTo(b.timeSec));
  }

  void removeComment(String id) {
    state = state.where((c) => c.id != id).toList();
  }

  /// استبدال كامل — يُستخدم عند فتح مشروع/استعادة autosave.
  void replaceAll(List<TimelineComment> comments) {
    state = [...comments]..sort((a, b) => a.timeSec.compareTo(b.timeSec));
  }

  void clearComments() {
    state = [];
  }
}

final commentsProvider = StateNotifierProvider<CommentsNotifier, List<TimelineComment>>((ref) {
  return CommentsNotifier();
});
