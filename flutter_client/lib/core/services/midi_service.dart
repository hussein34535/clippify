import 'package:flutter/foundation.dart';

typedef MidiCallback = void Function(MidiEvent event);

class MidiEvent {
  final String type;
  final int channel;
  final int? note;
  final int? controller;
  final int value;

  MidiEvent({
    required this.type,
    required this.channel,
    this.note,
    this.controller,
    required this.value,
  });
}

class MidiService {
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;
  MidiService._internal();

  final Set<MidiCallback> _listeners = {};
  bool _enabled = false;

  Future<bool> enable() async {
    if (_enabled) return true;
    debugPrint('[MIDI] Desktop MIDI not yet implemented (requires platform plugin)');
    _enabled = true;
    return true;
  }

  void handleMessage(MidiEvent event) {
    for (final cb in _listeners) {
      cb(event);
    }
  }

  VoidCallback onMessage(MidiCallback cb) {
    _listeners.add(cb);
    return () => _listeners.remove(cb);
  }

  List<Map<String, String>> listDevices() {
    return [];
  }

  bool isEnabled() => _enabled;
}

const Map<String, String> defaultMidiMappings = {
  'cc:64': 'playback.play',
  'cc:65': 'playback.pause',
  'cc:66': 'playback.toggle_fullscreen',
  'cc:67': 'timeline.undo',
  'cc:68': 'timeline.redo',
  'noteon:60': 'timeline.add_marker',
  'noteon:62': 'timeline.split_clip',
  'noteon:64': 'timeline.delete_clip',
};

String buildMappingKey(MidiEvent event) {
  return '${event.type}:${event.controller ?? event.note}';
}
