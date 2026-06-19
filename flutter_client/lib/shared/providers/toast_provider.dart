import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ToastType { success, error, info }

class ToastMessage {
  final String id;
  final String message;
  final ToastType type;
  ToastMessage({required this.id, required this.message, required this.type});
}

class ToastNotifier extends StateNotifier<List<ToastMessage>> {
  ToastNotifier() : super([]);

  void addToast(String message, ToastType type) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    state = [...state, ToastMessage(id: id, message: message, type: type)];
    Future.delayed(const Duration(seconds: 3), () {
      removeToast(id);
    });
  }

  void removeToast(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void success(String msg) => addToast(msg, ToastType.success);
  void error(String msg) => addToast(msg, ToastType.error);
  void info(String msg) => addToast(msg, ToastType.info);
}

final toastProvider = StateNotifierProvider<ToastNotifier, List<ToastMessage>>((ref) {
  return ToastNotifier();
});
