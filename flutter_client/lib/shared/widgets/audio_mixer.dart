import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class VUMeter extends StatelessWidget {
  final double level; // 0.0 - 1.0
  final String label;
  final bool isVertical;

  const VUMeter({
    super.key,
    required this.level,
    this.label = '',
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isVertical) return _buildVertical();
    return _buildHorizontal();
  }

  Widget _buildHorizontal() {
    final clampedLevel = level.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: (clampedLevel * 100).round(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          clampedLevel < 0.7 ? const Color(0xFF10B981) : clampedLevel < 0.9 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                          clampedLevel < 0.7 ? const Color(0xFF059669) : clampedLevel < 0.9 ? const Color(0xFFD97706) : const Color(0xFFDC2626),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: (100 - (clampedLevel * 100).round()).clamp(0, 100),
                  child: Container(color: AppColors.background),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVertical() {
    final clampedLevel = level.clamp(0.0, 1.0);
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              width: 12,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Column(
                children: [
                  Expanded(
                    flex: ((1 - clampedLevel) * 100).round().clamp(0, 100),
                    child: Container(color: AppColors.background),
                  ),
                  Expanded(
                    flex: (clampedLevel * 100).round(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            clampedLevel < 0.7 ? const Color(0xFF10B981) : clampedLevel < 0.9 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(label, style: const TextStyle(fontSize: 8, color: AppColors.textSecondary)),
          ),
      ],
    );
  }
}

class AudioEQControls extends StatelessWidget {
  final double bass;
  final double mid;
  final double treble;
  final double volume;
  final ValueChanged<double> onBassChanged;
  final ValueChanged<double> onMidChanged;
  final ValueChanged<double> onTrebleChanged;
  final ValueChanged<double> onVolumeChanged;

  const AudioEQControls({
    super.key,
    required this.bass,
    required this.mid,
    required this.treble,
    required this.volume,
    required this.onBassChanged,
    required this.onMidChanged,
    required this.onTrebleChanged,
    required this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.volume_up_rounded, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Mixer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            VUMeter(level: volume * 0.5, isVertical: false),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text('${(volume * 100).round()}%', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildEQBand(context, 'Bass', bass, 50, onBassChanged),
        _buildEQBand(context, 'Mid', mid, 100, onMidChanged),
        _buildEQBand(context, 'Treble', treble, 150, onTrebleChanged),
        const Divider(height: 16, color: AppColors.divider),
        VUMeter(label: 'Master', level: volume * 0.5),
      ],
    );
  }

  Widget _buildEQBand(BuildContext context, String label, double value, double freq, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ),
          SizedBox(
            width: 30,
            child: Text('${freq.round()}Hz', style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: 1.0,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text('${(value * 100).round()}%', style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
