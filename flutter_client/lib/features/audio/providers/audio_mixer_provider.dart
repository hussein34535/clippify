import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AutomationMode { read, write, touch, latch }

class ChannelState {
  final double volume;
  final double pan;
  final bool mute;
  final bool solo;
  final AutomationMode automationMode;
  final double vuLevel;

  const ChannelState({
    this.volume = 1.0,
    this.pan = 0.0,
    this.mute = false,
    this.solo = false,
    this.automationMode = AutomationMode.read,
    this.vuLevel = 0.0,
  });

  ChannelState copyWith({
    double? volume,
    double? pan,
    bool? mute,
    bool? solo,
    AutomationMode? automationMode,
    double? vuLevel,
  }) =>
      ChannelState(
        volume: volume ?? this.volume,
        pan: pan ?? this.pan,
        mute: mute ?? this.mute,
        solo: solo ?? this.solo,
        automationMode: automationMode ?? this.automationMode,
        vuLevel: vuLevel ?? this.vuLevel,
      );
}

class AudioMixerState {
  final Map<String, ChannelState> channels;
  final double masterVolume;
  final double masterVuLevel;
  final Set<String> soloedTracks;

  const AudioMixerState({
    this.channels = const {},
    this.masterVolume = 1.0,
    this.masterVuLevel = 0.0,
    this.soloedTracks = const {},
  });

  AudioMixerState copyWith({
    Map<String, ChannelState>? channels,
    double? masterVolume,
    double? masterVuLevel,
    Set<String>? soloedTracks,
  }) =>
      AudioMixerState(
        channels: channels ?? this.channels,
        masterVolume: masterVolume ?? this.masterVolume,
        masterVuLevel: masterVuLevel ?? this.masterVuLevel,
        soloedTracks: soloedTracks ?? this.soloedTracks,
      );

  bool get hasAnySolo => soloedTracks.isNotEmpty;

  bool isAudible(String trackId) {
    final ch = channels[trackId];
    if (ch == null) return true;
    if (ch.mute) return false;
    if (hasAnySolo) return soloedTracks.contains(trackId);
    return true;
  }
}

class AudioMixerNotifier extends StateNotifier<AudioMixerState> {
  AudioMixerNotifier() : super(const AudioMixerState());

  void addChannel(String trackId, {double initialVolume = 1.0, double initialPan = 0.0}) {
    if (state.channels.containsKey(trackId)) return;
    state = state.copyWith(
      channels: Map<String, ChannelState>.from(state.channels)
        ..[trackId] = ChannelState(volume: initialVolume, pan: initialPan),
    );
  }

  void removeChannel(String trackId) {
    final updated = Map<String, ChannelState>.from(state.channels)..remove(trackId);
    final updatedSolo = Set<String>.from(state.soloedTracks)..remove(trackId);
    state = state.copyWith(channels: updated, soloedTracks: updatedSolo);
  }

  void setVolume(String trackId, double volume) {
    _updateChannel(trackId, (c) => c.copyWith(volume: volume.clamp(0.0, 4.0)));
  }

  void setPan(String trackId, double pan) {
    _updateChannel(trackId, (c) => c.copyWith(pan: pan.clamp(-1.0, 1.0)));
  }

  void toggleMute(String trackId) {
    _updateChannel(trackId, (c) => c.copyWith(mute: !c.mute));
  }

  void toggleSolo(String trackId) {
    final updated = Set<String>.from(state.soloedTracks);
    if (updated.contains(trackId)) {
      updated.remove(trackId);
    } else {
      updated.add(trackId);
    }
    _updateChannel(trackId, (c) => c.copyWith(solo: updated.contains(trackId)));
    state = state.copyWith(soloedTracks: updated);
  }

  void setAutomationMode(String trackId, AutomationMode mode) {
    _updateChannel(trackId, (c) => c.copyWith(automationMode: mode));
  }

  void setVuLevel(String trackId, double level) {
    _updateChannel(trackId, (c) => c.copyWith(vuLevel: level.clamp(0.0, 1.0)));
  }

  void setMasterVolume(double volume) {
    state = state.copyWith(masterVolume: volume.clamp(0.0, 4.0));
  }

  void setMasterVuLevel(double level) {
    state = state.copyWith(masterVuLevel: level.clamp(0.0, 1.0));
  }

  void resetChannel(String trackId) {
    _updateChannel(trackId, (_) => const ChannelState());
  }

  void resetAll() {
    state = const AudioMixerState();
  }

  void _updateChannel(String trackId, ChannelState Function(ChannelState) update) {
    final existing = state.channels[trackId];
    if (existing == null) return;
    state = state.copyWith(
      channels: Map<String, ChannelState>.from(state.channels)
        ..[trackId] = update(existing),
    );
  }
}

final audioMixerProvider = StateNotifierProvider<AudioMixerNotifier, AudioMixerState>((ref) {
  return AudioMixerNotifier();
});
