import '../../../core/models/timeline_models.dart';

class TextPreset {
  final String name;
  final String description;
  final TextClip Function(String id, double startTime, double endTime) createClip;

  const TextPreset({
    required this.name,
    required this.description,
    required this.createClip,
  });
}

class TextPresets {
  static const List<TextPreset> presets = [
    TextPreset(
      name: 'عنوان بسيط',
      description: 'نص أبيض نظيف في المنتصف',
      createClip: _createSimpleTitle,
    ),
    TextPreset(
      name: 'Lower Third',
      description: 'نص في الأسفل مع خلفية',
      createClip: _createLowerThird,
    ),
    TextPreset(
      name: 'ترجمة',
      description: 'نص في الأسفل مع خلفية شبه شفافة',
      createClip: _createSubtitle,
    ),
    TextPreset(
      name: 'دعوة للعمل',
      description: 'نص عريض وملون مع حركة',
      createClip: _createCallToAction,
    ),
    TextPreset(
      name: 'اقتباس',
      description: 'نص مائل بخط أنيق',
      createClip: _createQuote,
    ),
    TextPreset(
      name: 'تحذير',
      description: 'نص أحمر عريض',
      createClip: _createWarning,
    ),
    TextPreset(
      name: 'مقدمة',
      description: 'نص كبير مع حركة دخول',
      createClip: _createIntro,
    ),
    TextPreset(
      name: 'خاتمة',
      description: 'نص مع حركة تلاشي',
      createClip: _createOutro,
    ),
    TextPreset(
      name: 'حساب اجتماعي',
      description: '@username style',
      createClip: _createSocialHandle,
    ),
    TextPreset(
      name: 'Caption',
      description: 'TikTok-style caption',
      createClip: _createCaption,
    ),
  ];

  static TextClip _createSimpleTitle(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'عنوان النص',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Roboto',
      fontSize: 64,
      colorValue: 0xFFFFFFFF,
      alignment: 'center',
      isBold: true,
      shadowBlur: 4,
      shadowColorValue: 0x80000000,
      shadowOffsetX: 2,
      shadowOffsetY: 2,
    );
  }

  static TextClip _createLowerThird(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'الاسم هنا',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Arial',
      fontSize: 48,
      colorValue: 0xFFFFFFFF,
      backgroundColorValue: 0xCC000000,
      alignment: 'left',
      isBold: true,
    );
  }

  static TextClip _createSubtitle(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'نص الترجمة هنا',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Arial',
      fontSize: 36,
      colorValue: 0xFFFFFFFF,
      backgroundColorValue: 0x80000000,
      alignment: 'center',
    );
  }

  static TextClip _createCallToAction(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'اشترك الآن!',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Impact',
      fontSize: 72,
      colorValue: 0xFFFFD700,
      strokeColorValue: 0xFF000000,
      strokeWidth: 3,
      alignment: 'center',
      isBold: true,
      animationType: 'scale_in',
      animationDuration: 0.5,
    );
  }

  static TextClip _createQuote(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: '"اقتباس ملهم هنا"',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Georgia',
      fontSize: 48,
      colorValue: 0xFFFFFFFF,
      alignment: 'center',
      isItalic: true,
      shadowBlur: 6,
      shadowColorValue: 0x80000000,
    );
  }

  static TextClip _createWarning(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'تحذير!',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Impact',
      fontSize: 80,
      colorValue: 0xFFFF0000,
      strokeColorValue: 0xFFFFFFFF,
      strokeWidth: 2,
      alignment: 'center',
      isBold: true,
      animationType: 'scale_in',
      animationDuration: 0.3,
    );
  }

  static TextClip _createIntro(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'مقدمة الفيديو',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Roboto',
      fontSize: 96,
      colorValue: 0xFFFFFFFF,
      alignment: 'center',
      isBold: true,
      animationType: 'fade_in',
      animationDuration: 1.0,
    );
  }

  static TextClip _createOutro(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'شكراً للمشاهدة',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Roboto',
      fontSize: 72,
      colorValue: 0xFFFFFFFF,
      alignment: 'center',
      isBold: true,
      animationType: 'fade_out',
      animationDuration: 1.0,
    );
  }

  static TextClip _createSocialHandle(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: '@username',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Arial',
      fontSize: 40,
      colorValue: 0xFF1DA1F2,
      backgroundColorValue: 0xCCFFFFFF,
      alignment: 'center',
      isBold: true,
    );
  }

  static TextClip _createCaption(String id, double startTime, double endTime) {
    return TextClip(
      id: id,
      text: 'Caption text here',
      startTime: startTime,
      endTime: endTime,
      fontFamily: 'Arial',
      fontSize: 44,
      colorValue: 0xFFFFFFFF,
      backgroundColorValue: 0xCC000000,
      alignment: 'center',
      isBold: true,
      animationType: 'slide_up',
      animationDuration: 0.4,
    );
  }
}
