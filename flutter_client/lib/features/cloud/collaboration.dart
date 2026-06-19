import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class CollaborationManager {
  final String _userId;
  final String _userName;
  WebSocket? _ws;
  Timer? _pingTimer;
  bool _connected = false;

  CollaborationManager({required String userId, required String userName})
      : _userId = userId, _userName = userName;

  bool get connected => _connected;

  Future<void> connect(String host) async {
    try {
      _ws = await WebSocket.connect(host);
      _connected = true;
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sendPing());
      debugPrint('[Collaboration] Connected to $host');
    } catch (e) {
      debugPrint('[Collaboration] Connection failed: $e');
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _ws?.close();
    _connected = false;
  }

  void sendAction(String action, Map<String, dynamic> data) {
    if (!_connected) return;
    final msg = jsonEncode({'action': action, 'data': data, 'userId': _userId, 'userName': _userName});
    _ws?.add(msg);
  }

  void sendCursor(double x, double y) {
    sendAction('cursor', {'x': x, 'y': y});
  }

  void sendEdit(String action, Map<String, dynamic> payload) {
    sendAction('edit', {'editAction': action, 'payload': payload});
  }

  void sendChat(String text) {
    sendAction('chat', {'text': text});
  }

  void _sendPing() {
    sendAction('ping', {});
  }

  void dispose() {
    disconnect();
  }
}
