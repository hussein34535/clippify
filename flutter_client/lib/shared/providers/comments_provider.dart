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

  void clearComments() {
    state = [];
  }
}

final commentsProvider = StateNotifierProvider<CommentsNotifier, List<TimelineComment>>((ref) {
  return CommentsNotifier();
});
