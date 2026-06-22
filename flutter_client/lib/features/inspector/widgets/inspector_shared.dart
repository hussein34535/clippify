import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class InspectorSectionHeader extends StatelessWidget {
  final String title;
  const InspectorSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFamily: 'Outfit',
              fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'],
            ),
          ),
        ],
      ),
    );
  }
}

class InspectorPropertySlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const InspectorPropertySlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class InspectorNumberInput extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const InspectorNumberInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<InspectorNumberInput> createState() => _InspectorNumberInputState();
}

class _InspectorNumberInputState extends State<InspectorNumberInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant InspectorNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 11, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
              ),
              onSubmitted: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null) {
                  widget.onChanged(parsed);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class InspectorPlaceholder extends StatelessWidget {
  final String message;
  const InspectorPlaceholder({super.key, this.message = 'No clip selected'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}
