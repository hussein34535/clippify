abstract class AudioEffect {
  final String name;
  final String id;
  bool enabled;
  double mix;

  AudioEffect({required this.name, required this.id, this.enabled = true, this.mix = 1.0});

  double process(double sample, int channel, double sampleRate);
}

class EQEffect extends AudioEffect {
  double bass;  // 0-1, maps to gain at low frequencies
  double mid;   // 0-1
  double treble; // 0-1

  double _low = 0, _mid = 0, _high = 0;

  EQEffect({super.id = 'eq', super.name = 'EQ', this.bass = 0.5, this.mid = 0.5, this.treble = 0.5});

  @override
  double process(double sample, int channel, double sampleRate) {
    _low += (sample - _low) * 0.005;
    _high += (sample - _high) * 0.1;
    _mid = sample - _low - _high;
    final result = _low * (bass * 2) + _mid * (mid * 2) + _high * (treble * 2);
    return (1 - mix) * sample + mix * result;
  }
}

class CompressorEffect extends AudioEffect {
  double threshold; // 0-1
  double ratio;     // 1:1 to 20:1
  double attack;    // seconds
  double release;   // seconds

  double _envelope = 0;

  CompressorEffect({
    super.id = 'compressor', super.name = 'Compressor',
    this.threshold = 0.5, this.ratio = 4, this.attack = 0.002, this.release = 0.1,
  });

  @override
  double process(double sample, int channel, double sampleRate) {
    final abs = sample.abs();
    final alpha = abs > _envelope ? (1.0 / (attack * sampleRate)) : (1.0 / (release * sampleRate));
    _envelope += (abs - _envelope) * alpha.clamp(0.0, 1.0);
    if (_envelope > threshold) {
      final reduction = (_envelope - threshold) * (1 - 1 / ratio);
      return sample * (1 - reduction / _envelope).clamp(0.0, 1.0);
    }
    return sample;
  }
}

class ReverbEffect extends AudioEffect {
  final List<double> _buffer;
  int _index = 0;
  final double decay;

  ReverbEffect({
    super.id = 'reverb', super.name = 'Reverb',
    int size = 44100, this.decay = 0.3,
  }) : _buffer = List.filled(size, 0.0);

  @override
  double process(double sample, int channel, double sampleRate) {
    _buffer[_index] = sample;
    double wet = 0;
    for (int i = 1; i < 5; i++) {
      final delay = (_buffer.length ~/ (i * 2));
      final pos = (_index - delay) % _buffer.length;
      wet += _buffer[pos] * (decay / i);
    }
    _index = (_index + 1) % _buffer.length;
    return (1 - mix) * sample + mix * wet;
  }
}

class DelayEffect extends AudioEffect {
  final List<double> _buffer;
  int _index = 0;
  final double feedback;

  DelayEffect({
    super.id = 'delay', super.name = 'Delay',
    int delayMs = 200, double sampleRate = 44100, this.feedback = 0.3,
  }) : _buffer = List.filled((delayMs * sampleRate / 1000).round(), 0.0);

  @override
  double process(double sample, int channel, double sampleRate) {
    final delayed = _buffer[_index];
    _buffer[_index] = sample + delayed * feedback;
    _index = (_index + 1) % _buffer.length;
    return (1 - mix) * sample + mix * delayed;
  }
}

class DistortionEffect extends AudioEffect {
  final double drive;

  DistortionEffect({
    super.id = 'distortion', super.name = 'Distortion',
    this.drive = 2.0,
  });

  @override
  double process(double sample, int channel, double sampleRate) {
    final shaped = (sample * drive).clamp(-1.0, 1.0);
    return (1 - mix) * sample + mix * shaped;
  }
}

class FilterEffect extends AudioEffect {
  final String filterType; // 'lowpass', 'highpass', 'bandpass'
  final double cutoff;
  final double resonance;
  double _prevOutput = 0;
  double _prevInput = 0;

  FilterEffect({
    super.id = 'filter', super.name = 'Filter',
    this.filterType = 'lowpass', this.cutoff = 0.5, this.resonance = 0.5,
  });

  @override
  double process(double sample, int channel, double sampleRate) {
    final f = cutoff.clamp(0.01, 0.99);
    final r = resonance * 4 * (1 - f);
    final output = sample * (1 - r) + _prevOutput * r - _prevInput * (r / 2);
    _prevInput = sample;
    _prevOutput = output;
    return (1 - mix) * sample + mix * output.clamp(-1.0, 1.0);
  }
}

class AudioEffectChain {
  final List<AudioEffect> effects = [];

  void add(AudioEffect effect) => effects.add(effect);
  void remove(String id) => effects.removeWhere((e) => e.id == id);
  void clear() => effects.clear();
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final effect = effects.removeAt(oldIndex);
    effects.insert(newIndex, effect);
  }

  double process(double sample, int channel, double sampleRate) {
    double output = sample;
    for (final effect in effects) {
      if (effect.enabled) {
        output = effect.process(output, channel, sampleRate);
      }
    }
    return output;
  }
}

class AudioMixerChannel {
  final String id;
  final String name;
  double volume;
  double pan;
  bool muted;
  bool solo;
  final AudioEffectChain effects;

  AudioMixerChannel({
    required this.id,
    required this.name,
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.solo = false,
  }) : effects = AudioEffectChain();
}

class AudioMixer {
  final List<AudioMixerChannel> channels = [];
  double masterVolume = 1.0;

  AudioMixerChannel addChannel(String id, String name) {
    final channel = AudioMixerChannel(id: id, name: name);
    channels.add(channel);
    return channel;
  }

  void removeChannel(String id) => channels.removeWhere((c) => c.id == id);

  bool get hasSolo => channels.any((c) => c.solo);
}
