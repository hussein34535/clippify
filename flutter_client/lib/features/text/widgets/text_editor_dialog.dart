import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';

class TextEditorDialog extends StatefulWidget {
  final TextClip? existingClip;

  const TextEditorDialog({super.key, this.existingClip});

  @override
  State<TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<TextEditorDialog> {
  late TextEditingController _textController;
  late String _fontFamily;
  late double _fontSize;
  late int _colorValue;
  late int? _backgroundColorValue;
  late int? _strokeColorValue;
  late double _strokeWidth;
  late String _alignment;
  late bool _isBold;
  late bool _isItalic;
  late double _shadowBlur;
  late int? _shadowColorValue;
  late double _shadowOffsetX;
  late double _shadowOffsetY;
  late String? _animationType;
  late double _animationDuration;

  final List<String> _fontFamilies = [
    'Roboto',
    'Arial',
    'Helvetica',
    'Times New Roman',
    'Courier New',
    'Georgia',
    'Verdana',
    'Impact',
    'Comic Sans MS',
    'Trebuchet MS',
    'Palatino',
    'Garamond',
    'Bookman',
    'Avant Garde',
    'Cairo',
    'Tajawal',
    'Almarai',
    'IBM Plex Sans Arabic',
    'Noto Sans Arabic',
    'Amiri',
  ];

  final List<String> _animationTypes = [
    'none',
    'fade_in',
    'fade_out',
    'slide_up',
    'slide_down',
    'slide_left',
    'slide_right',
    'scale_in',
    'scale_out',
    'typewriter',
  ];

  @override
  void initState() {
    super.initState();
    final clip = widget.existingClip;
    _textController = TextEditingController(text: clip?.text ?? '');
    _fontFamily = clip?.fontFamily ?? 'Roboto';
    _fontSize = clip?.fontSize ?? 48.0;
    _colorValue = clip?.colorValue ?? 0xFFFFFFFF;
    _backgroundColorValue = clip?.backgroundColorValue;
    _strokeColorValue = clip?.strokeColorValue;
    _strokeWidth = clip?.strokeWidth ?? 0.0;
    _alignment = clip?.alignment ?? 'center';
    _isBold = clip?.isBold ?? false;
    _isItalic = clip?.isItalic ?? false;
    _shadowBlur = clip?.shadowBlur ?? 0.0;
    _shadowColorValue = clip?.shadowColorValue;
    _shadowOffsetX = clip?.shadowOffsetX ?? 0.0;
    _shadowOffsetY = clip?.shadowOffsetY ?? 0.0;
    _animationType = clip?.animationType;
    _animationDuration = clip?.animationDuration ?? 0.5;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Color _intToColor(int value) => Color(value);
  int _colorToInt(Color color) => color.toARGB32();

  Future<void> _pickColor(
    BuildContext context,
    String title,
    int currentColor,
    ValueChanged<int> onColorChanged,
  ) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        title: title,
        initialColor: _intToColor(currentColor),
      ),
    );
    if (color != null) {
      onColorChanged(_colorToInt(color));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existingClip == null ? 'إضافة نص' : 'تعديل النص',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('النص', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _textController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'اكتب النص هنا...',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          const Text('الخط', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _fontFamily,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'نوع الخط',
                            ),
                            items: _fontFamilies.map((font) {
                              return DropdownMenuItem(
                                value: font,
                                child: Text(font, style: TextStyle(fontFamily: font)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _fontFamily = value);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Text('الحجم: ${_fontSize.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Slider(
                            value: _fontSize,
                            min: 12,
                            max: 120,
                            divisions: 108,
                            label: _fontSize.toInt().toString(),
                            onChanged: (value) => setState(() => _fontSize = value),
                          ),
                          const SizedBox(height: 16),
                          const Text('الألوان', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _ColorButton(
                                  label: 'لون النص',
                                  color: _intToColor(_colorValue),
                                  onPressed: () => _pickColor(
                                    context,
                                    'لون النص',
                                    _colorValue,
                                    (value) => setState(() => _colorValue = value),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ColorButton(
                                  label: 'لون الخلفية',
                                  color: _backgroundColorValue != null ? _intToColor(_backgroundColorValue!) : null,
                                  onPressed: () => _pickColor(
                                    context,
                                    'لون الخلفية',
                                    _backgroundColorValue ?? 0x80000000,
                                    (value) => setState(() => _backgroundColorValue = value),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _ColorButton(
                                  label: 'لون الحد',
                                  color: _strokeColorValue != null ? _intToColor(_strokeColorValue!) : null,
                                  onPressed: () => _pickColor(
                                    context,
                                    'لون الحد',
                                    _strokeColorValue ?? 0xFF000000,
                                    (value) => setState(() => _strokeColorValue = value),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('عرض الحد: ${_strokeWidth.toStringAsFixed(1)}'),
                                    Slider(
                                      value: _strokeWidth,
                                      min: 0,
                                      max: 10,
                                      divisions: 20,
                                      label: _strokeWidth.toStringAsFixed(1),
                                      onChanged: (value) => setState(() => _strokeWidth = value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('المحاذاة', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.format_align_left),
                                color: _alignment == 'left' ? Colors.blue : null,
                                onPressed: () => setState(() => _alignment = 'left'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.format_align_center),
                                color: _alignment == 'center' ? Colors.blue : null,
                                onPressed: () => setState(() => _alignment = 'center'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.format_align_right),
                                color: _alignment == 'right' ? Colors.blue : null,
                                onPressed: () => setState(() => _alignment = 'right'),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(Icons.format_bold),
                                color: _isBold ? Colors.blue : null,
                                onPressed: () => setState(() => _isBold = !_isBold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.format_italic),
                                color: _isItalic ? Colors.blue : null,
                                onPressed: () => setState(() => _isItalic = !_isItalic),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('الظل', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _ColorButton(
                                  label: 'لون الظل',
                                  color: _shadowColorValue != null ? _intToColor(_shadowColorValue!) : null,
                                  onPressed: () => _pickColor(
                                    context,
                                    'لون الظل',
                                    _shadowColorValue ?? 0x80000000,
                                    (value) => setState(() => _shadowColorValue = value),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ضبابية: ${_shadowBlur.toStringAsFixed(1)}'),
                                    Slider(
                                      value: _shadowBlur,
                                      min: 0,
                                      max: 20,
                                      divisions: 40,
                                      label: _shadowBlur.toStringAsFixed(1),
                                      onChanged: (value) => setState(() => _shadowBlur = value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('إزاحة X: ${_shadowOffsetX.toStringAsFixed(1)}'),
                                    Slider(
                                      value: _shadowOffsetX,
                                      min: -20,
                                      max: 20,
                                      divisions: 40,
                                      label: _shadowOffsetX.toStringAsFixed(1),
                                      onChanged: (value) => setState(() => _shadowOffsetX = value),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('إزاحة Y: ${_shadowOffsetY.toStringAsFixed(1)}'),
                                    Slider(
                                      value: _shadowOffsetY,
                                      min: -20,
                                      max: 20,
                                      divisions: 40,
                                      label: _shadowOffsetY.toStringAsFixed(1),
                                      onChanged: (value) => setState(() => _shadowOffsetY = value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('الحركة', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _animationType ?? 'none',
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'نوع الحركة',
                            ),
                            items: _animationTypes.map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(_getAnimationLabel(type)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _animationType = value == 'none' ? null : value);
                            },
                          ),
                          const SizedBox(height: 8),
                          Text('مدة الحركة: ${_animationDuration.toStringAsFixed(1)} ثانية'),
                          Slider(
                            value: _animationDuration,
                            min: 0.1,
                            max: 3.0,
                            divisions: 29,
                            label: _animationDuration.toStringAsFixed(1),
                            onChanged: (value) => setState(() => _animationDuration = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('معاينة', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: _buildPreview(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _textController.text.isEmpty
                      ? null
                      : () {
                          final clip = TextClip(
                            id: widget.existingClip?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                            text: _textController.text,
                            startTime: widget.existingClip?.startTime ?? 0,
                            endTime: widget.existingClip?.endTime ?? 5,
                            fontFamily: _fontFamily,
                            fontSize: _fontSize,
                            colorValue: _colorValue,
                            backgroundColorValue: _backgroundColorValue,
                            strokeColorValue: _strokeColorValue,
                            strokeWidth: _strokeWidth,
                            alignment: _alignment,
                            isBold: _isBold,
                            isItalic: _isItalic,
                            shadowBlur: _shadowBlur,
                            shadowColorValue: _shadowColorValue,
                            shadowOffsetX: _shadowOffsetX,
                            shadowOffsetY: _shadowOffsetY,
                            animationType: _animationType,
                            animationDuration: _animationDuration,
                          );
                          Navigator.of(context).pop(clip);
                        },
                  child: Text(widget.existingClip == null ? 'إضافة' : 'حفظ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        _textController.text.isEmpty ? 'معاينة النص' : _textController.text,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: _fontSize / 2,
          color: _intToColor(_colorValue),
          fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _shadowColorValue != null
              ? [
                  Shadow(
                    blurRadius: _shadowBlur,
                    color: _intToColor(_shadowColorValue!),
                    offset: Offset(_shadowOffsetX, _shadowOffsetY),
                  ),
                ]
              : null,
        ),
        textAlign: _alignment == 'left'
            ? TextAlign.left
            : _alignment == 'right'
                ? TextAlign.right
                : TextAlign.center,
      ),
    );
  }

  String _getAnimationLabel(String type) {
    switch (type) {
      case 'none':
        return 'بدون';
      case 'fade_in':
        return 'تلاشي للداخل';
      case 'fade_out':
        return 'تلاشي للخارج';
      case 'slide_up':
        return 'انزلاق للأعلى';
      case 'slide_down':
        return 'انزلاق للأسفل';
      case 'slide_left':
        return 'انزلاق لليسار';
      case 'slide_right':
        return 'انزلاق لليمين';
      case 'scale_in':
        return 'تكبير';
      case 'scale_out':
        return 'تصغير';
      case 'typewriter':
        return 'آلة كاتبة';
      default:
        return type;
    }
  }
}

class _ColorButton extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback onPressed;

  const _ColorButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color ?? Colors.transparent,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;

  const _ColorPickerDialog({
    required this.title,
    required this.initialColor,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selectedColor;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _hexController = TextEditingController(
      text: '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _updateColorFromHex(String hex) {
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    if (hex.length == 8) {
      try {
        final color = Color(int.parse(hex, radix: 16));
        setState(() => _selectedColor = color);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: _selectedColor,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hexController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'HEX',
                prefixText: '#',
              ),
              onChanged: _updateColorFromHex,
            ),
            const SizedBox(height: 16),
            const Text('ألوان سريعة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Colors.white,
                Colors.black,
                Colors.red,
                Colors.green,
                Colors.blue,
                Colors.yellow,
                Colors.orange,
                Colors.purple,
                Colors.pink,
                Colors.cyan,
                Colors.brown,
                Colors.grey,
              ].map((color) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                      _hexController.text = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selectedColor),
                  child: const Text('اختيار'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
