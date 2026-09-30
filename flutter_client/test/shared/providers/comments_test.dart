import 'package:flutter_client/shared/providers/comments_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimelineComment json', () {
    test('roundtrip preserves fields', () {
      final c = TimelineComment(
        id: 'c1',
        timeSec: 3.5,
        text: 'ملاحظة على القصّة',
        createdAt: DateTime.utc(2026, 5, 1, 12),
      );
      final back = TimelineComment.fromJson(c.toJson());
      expect(back.id, 'c1');
      expect(back.timeSec, 3.5);
      expect(back.text, 'ملاحظة على القصّة');
      expect(back.createdAt, DateTime.utc(2026, 5, 1, 12));
    });

    test('fromJson tolerates garbage', () {
      final back = TimelineComment.fromJson({'foo': 1});
      expect(back.text, '');
      expect(back.timeSec, 0.0);
      expect(back.id, isNotEmpty);
    });
  });

  group('CommentsNotifier.replaceAll', () {
    test('replaces and sorts by time', () {
      final n = CommentsNotifier();
      n.addComment(9, 'late');
      n.replaceAll([
        TimelineComment(
            id: 'a',
            timeSec: 5,
            text: 'a',
            createdAt: DateTime.now()),
        TimelineComment(
            id: 'b', timeSec: 1, text: 'b', createdAt: DateTime.now()),
      ]);
      expect(n.state.map((c) => c.id).toList(), ['b', 'a']);
      n.dispose();
    });
  });
}
