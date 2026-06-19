import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../timeline/providers/timeline_provider.dart';

class SubtitleEditorWidget extends ConsumerStatefulWidget {
  final SubtitleClip clip;

  const SubtitleEditorWidget({
    super.key,
    required this.clip,
  });

  @override
  ConsumerState<SubtitleEditorWidget> createState() => _SubtitleEditorWidgetState();
}

class _SubtitleEditorWidgetState extends ConsumerState<SubtitleEditorWidget> {
  late TextEditingController _textController;
  late TextEditingController _startController;
  late TextEditingController _endController;
  late TextEditingController _primaryColorController;
  late TextEditingController _strokeColorController;

  final List<Map<String, dynamic>> _presetColors = [
    {'name': 'أصفر تيك توك', 'hex': '#FFFF00', 'color': const Color(0xFFFFD60A)},
    {'name': 'أبيض ناصع', 'hex': '#FFFFFF', 'color': Colors.white},
    {'name': 'أخضر نيون', 'hex': '#00FF00', 'color': const Color(0xFF30D158)},
    {'name': 'أحمر صارخ', 'hex': '#FF0000', 'color': const Color(0xFFFF453A)},
    {'name': 'أزرق سماوي', 'hex': '#00F0FF', 'color': const Color(0xFF64D2FF)},
    {'name': 'وردي زاهي', 'hex': '#FF00FF', 'color': const Color(0xFFFF375F)},
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.clip.text);
    _startController = TextEditingController(text: widget.clip.startTime.toStringAsFixed(2));
    _endController = TextEditingController(text: widget.clip.endTime.toStringAsFixed(2));
    _primaryColorController = TextEditingController(text: widget.clip.style.primaryColor);
    _strokeColorController = TextEditingController(text: widget.clip.style.strokeColor);
  }

  @override
  void didUpdateWidget(covariant SubtitleEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.id != widget.clip.id) {
      _textController.text = widget.clip.text;
      _startController.text = widget.clip.startTime.toStringAsFixed(2);
      _endController.text = widget.clip.endTime.toStringAsFixed(2);
      _primaryColorController.text = widget.clip.style.primaryColor;
      _strokeColorController.text = widget.clip.style.strokeColor;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _startController.dispose();
    _endController.dispose();
    _primaryColorController.dispose();
    _strokeColorController.dispose();
    super.dispose();
  }

  void _updateClipText(String text) {
    ref.read(timelineProvider.notifier).updateSubtitleClip(widget.clip.id, (c) {
      return SubtitleClip(
        id: c.id,
        text: text,
        startTime: c.startTime,
        endTime: c.endTime,
        style: c.style,
      );
    });
  }

  void _updateClipTiming(String field, double val) {
    ref.read(timelineProvider.notifier).updateSubtitleClip(widget.clip.id, (c) {
      return SubtitleClip(
        id: c.id,
        text: c.text,
        startTime: field == 'start' ? val.clamp(0.0, c.endTime) : c.startTime,
        endTime: field == 'end' ? val.clamp(c.startTime, double.infinity) : c.endTime,
        style: c.style,
      );
    });
  }

  void _updateClipStyle(SubtitleClipStyle newStyle) {
    ref.read(timelineProvider.notifier).updateSubtitleClip(widget.clip.id, (c) {
      return SubtitleClip(
        id: c.id,
        text: c.text,
        startTime: c.startTime,
        endTime: c.endTime,
        style: newStyle,
      );
    });
  }

  Color _parseHexColor(String hex) {
    try {
      final cleanHex = hex.replaceAll('#', '');
      if (cleanHex.length == 6) {
        return Color(int.parse('FF$cleanHex', radix: 16));
      } else if (cleanHex.length == 8) {
        return Color(int.parse(cleanHex, radix: 16));
      }
    } catch (_) {}
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.clip.style;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.subtitles_rounded, color: AppColors.primary, size: 18),
            const Text(
              'محرر الترجمة المتقدم (Subtitle Editor)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 📝 نص الترجمة
        _buildSectionHeader('نص الترجمة'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _textController,
          maxLines: 3,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'اكتب نص الترجمة هنا...',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          onChanged: _updateClipText,
        ),

        const Divider(height: 24, color: AppColors.divider),

        // ⏱️ التوقيت
        _buildSectionHeader('التوقيت (بالثواني)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildNumberField(
                label: 'وقت النهاية',
                controller: _endController,
                onChanged: (val) => _updateClipTiming('end', val),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildNumberField(
                label: 'وقت البدء',
                controller: _startController,
                onChanged: (val) => _updateClipTiming('start', val),
              ),
            ),
          ],
        ),

        const Divider(height: 24, color: AppColors.divider),

        // 🔠 نوع وحجم الخط
        _buildSectionHeader('تنسيق الخط والنوع'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: style.fontName,
              isExpanded: true,
              dropdownColor: AppColors.card,
              items: const [
                DropdownMenuItem(value: 'Impact', child: Text('Impact (TikTok Bold)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'Inter', child: Text('Inter (Sleek Sans)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'Arial', child: Text('Arial (Standard)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'Courier New', child: Text('Courier New (Typewriter)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'Georgia', child: Text('Georgia (Serif)', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  _updateClipStyle(style.copyWith(fontName: val));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildPropertySlider(
          label: 'حجم الخط',
          value: style.fontSize,
          min: 12.0,
          max: 120.0,
          onChanged: (val) => _updateClipStyle(style.copyWith(fontSize: val)),
        ),

        const Divider(height: 24, color: AppColors.divider),

        // 🎨 الألوان الأساسية
        _buildSectionHeader('اللون الأساسي للخط'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _primaryColorController,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
                decoration: InputDecoration(
                  prefixText: '#',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty) {
                    _updateClipStyle(style.copyWith(primaryColor: val.startsWith('#') ? val : '#$val'));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _parseHexColor(style.primaryColor),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Presets
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _presetColors.map((colorMap) {
            final isSelected = style.primaryColor.toUpperCase() == colorMap['hex'];
            return InkWell(
              onTap: () {
                setState(() {
                  _primaryColorController.text = colorMap['hex'];
                });
                _updateClipStyle(style.copyWith(primaryColor: colorMap['hex']));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorMap['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      colorMap['name'] as String,
                      style: TextStyle(fontSize: 9, color: isSelected ? Colors.white : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const Divider(height: 24, color: AppColors.divider),

        // 🎨 لون وحجم الحواف
        _buildSectionHeader('لون وعرض الحواف (Stroke)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _strokeColorController,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
                decoration: InputDecoration(
                  prefixText: '#',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty) {
                    _updateClipStyle(style.copyWith(strokeColor: val.startsWith('#') ? val : '#$val'));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _parseHexColor(style.strokeColor),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildPropertySlider(
          label: 'عرض الحافة',
          value: style.strokeWidth,
          min: 0.0,
          max: 10.0,
          onChanged: (val) => _updateClipStyle(style.copyWith(strokeWidth: val)),
        ),

        const Divider(height: 24, color: AppColors.divider),

        // 🎬 التأثيرات والحركة والموضع
        _buildSectionHeader('طريقة الظهور والموضع'),
        const SizedBox(height: 8),
        const Text('التحريك (Animation)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: style.animation,
              isExpanded: true,
              dropdownColor: AppColors.card,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('بدون تحريك (Static)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'pop_in', child: Text('تكبير مفاجئ (Pop In)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'fade_in', child: Text('ظهور تدريجي (Fade In)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'slide_up', child: Text('صعود لأعلى (Slide Up)', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  _updateClipStyle(style.copyWith(animation: val));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('الموضع (Alignment)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: style.alignment,
              isExpanded: true,
              dropdownColor: AppColors.card,
              items: const [
                DropdownMenuItem(value: 'center_bottom', child: Text('المنتصف بالأسفل', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'center_top', child: Text('المنتصف بالأعلى', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'center_middle', child: Text('المنتصف تماماً', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  _updateClipStyle(style.copyWith(alignment: val));
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
      textAlign: TextAlign.right,
    );
  }

  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: TextFormField(
            controller: controller,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.left,
            onChanged: (val) {
              final parsed = double.tryParse(val);
              if (parsed != null) {
                onChanged(parsed);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPropertySlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: AppColors.primary, fontFamily: 'monospace')),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

extension SubtitleClipStyleExtension on SubtitleClipStyle {
  SubtitleClipStyle copyWith({
    String? fontName,
    double? fontSize,
    String? primaryColor,
    String? strokeColor,
    double? strokeWidth,
    String? animation,
    String? alignment,
  }) {
    return SubtitleClipStyle(
      fontName: fontName ?? this.fontName,
      fontSize: fontSize ?? this.fontSize,
      primaryColor: primaryColor ?? this.primaryColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      animation: animation ?? this.animation,
      alignment: alignment ?? this.alignment,
    );
  }
}
