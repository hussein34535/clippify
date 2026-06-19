import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';

class TransitionPicker extends StatefulWidget {
  final Transition currentTransition;

  const TransitionPicker({super.key, required this.currentTransition});

  @override
  State<TransitionPicker> createState() => _TransitionPickerState();
}

class _TransitionPickerState extends State<TransitionPicker> {
  late String _selectedType;
  late double _duration;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentTransition.type;
    _duration = widget.currentTransition.duration;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اختر Transition',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: Transition.availableTypes.length,
                itemBuilder: (context, index) {
                  final type = Transition.availableTypes[index];
                  final isSelected = type == _selectedType;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedType = type;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.background,
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.divider,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getTransitionIcon(type),
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getTransitionName(type),
                            style: TextStyle(
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_selectedType != 'none') ...[
              const Text(
                'المدة (ثانية)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _duration,
                      min: 0.1,
                      max: 3.0,
                      divisions: 29,
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.divider,
                      onChanged: (value) {
                        setState(() {
                          _duration = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_duration.toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      Transition(type: _selectedType, duration: _duration),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('تطبيق'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTransitionIcon(String type) {
    switch (type) {
      case 'none':
        return Icons.block;
      case 'cross_dissolve':
        return Icons.blur_on;
      case 'fade_to_black':
        return Icons.brightness_1;
      case 'fade_to_white':
        return Icons.brightness_high;
      case 'wipe_left':
        return Icons.arrow_back;
      case 'wipe_right':
        return Icons.arrow_forward;
      case 'wipe_up':
        return Icons.arrow_upward;
      case 'wipe_down':
        return Icons.arrow_downward;
      case 'zoom_in':
        return Icons.zoom_in;
      case 'zoom_out':
        return Icons.zoom_out;
      case 'spin':
        return Icons.rotate_right;
      case 'blur':
        return Icons.blur_circular;
      default:
        return Icons.help;
    }
  }

  String _getTransitionName(String type) {
    switch (type) {
      case 'none':
        return 'بدون';
      case 'cross_dissolve':
        return 'Cross Dissolve';
      case 'fade_to_black':
        return 'Fade to Black';
      case 'fade_to_white':
        return 'Fade to White';
      case 'wipe_left':
        return 'Wipe Left';
      case 'wipe_right':
        return 'Wipe Right';
      case 'wipe_up':
        return 'Wipe Up';
      case 'wipe_down':
        return 'Wipe Down';
      case 'zoom_in':
        return 'Zoom In';
      case 'zoom_out':
        return 'Zoom Out';
      case 'spin':
        return 'Spin';
      case 'blur':
        return 'Blur';
      default:
        return type;
    }
  }
}
